extends "res://scripts/CombatUnit.gd"

# Survivor Saboteur (DESIGN_MASTER §7.3, v1) — the faction's zombie verb:
# Military FIGHTS the ecosystem, Tribal JOINS it, the Saboteur REDIRECTS
# its attention. v1 ships the sound grenade: a thrown noisemaker that
# detonates as a large NoiseBus event somewhere ELSE — remote control for
# the horde, the inverse of the Caller (he pulls zombies toward himself;
# the Saboteur throws their attention away). Unarmed otherwise.
#
# CONNECTED 2026-06-10 (Matt's go): produced by the SettlementHub; ground
# right-clicks route to throw_sound_grenade via CommandBus "sound_grenade"
# (rearming degrades to a plain move). Car-alarm traps + doctrines
# (Demolitionist / Whisperer) are [PROPOSED] — deferred.

const THROW_RANGE_PX := 224.0       # 7 tiles
const FLIGHT_TIME := 1.2            # sim seconds in the air
# Detonation magnitude: deliberately MEDIUM-horde tier (NoiseField medium
# threshold is 400). One grenade pulls a real response without handing the
# player a free CATASTROPHIC on a 15s timer. Balance-lab placeholder.
const GRENADE_NOISE := 450.0
const GRENADE_COOLDOWN := 15.0

const KITE_RANGE := 120.0
const KITE_SPEED := 34.0
const THREAT_CHECK_INTERVAL := 0.2

const SPRITE_ROOT := "res://assets/sprites/units/survivor/saboteur/"
const THROW_ANIM_HOLD := 0.5

var _threat_check_timer: float = 0.0
var _threat_cached = null
var _grenade_cooldown: float = 0.0
# One grenade in flight at a time: armed target + countdown. Fixed-tick
# accumulator (Rule #2); detonation order is position-independent (a single
# NoiseBus.emit), so no stable-sort concern.
var _flight_timer: float = 0.0
var _flight_target := Vector2.ZERO
var _grenade_in_flight: bool = false
# Approach-then-throw: set when ordered beyond range.
var _pending_throw_pos := Vector2.ZERO
var _has_pending_throw: bool = false


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _morale_enabled() -> bool:
	return true


func _ready() -> void:
	super._ready()
	_init_sprite()


func throw_sound_grenade(world_pos: Vector2) -> void:
	# The unit's verb — ground right-clicks route here (connected 2026-06-10).
	if _grenade_cooldown > 0.0 or _grenade_in_flight:
		# Rearming: degrade to a plain move so right-click never goes dead.
		move_to(world_pos)
		return
	if global_position.distance_to(world_pos) > THROW_RANGE_PX:
		# Walk into range first, throw on arrival.
		_pending_throw_pos = world_pos
		_has_pending_throw = true
		move_to(world_pos)
		return
	_launch_grenade(world_pos)


func _launch_grenade(world_pos: Vector2) -> void:
	_grenade_in_flight = true
	_flight_target = world_pos
	_flight_timer = FLIGHT_TIME
	_grenade_cooldown = GRENADE_COOLDOWN
	_attack_anim_timer = THROW_ANIM_HOLD
	queue_redraw()


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	_grenade_cooldown = max(0.0, _grenade_cooldown - delta)
	if use_sprite:
		_update_sprite_animation()
	# Grenade flight: detonate where it was thrown, not where we are now.
	if _grenade_in_flight:
		_flight_timer -= delta
		if _flight_timer <= 0.0:
			_grenade_in_flight = false
			NoiseBus.emit(_flight_target, GRENADE_NOISE)
			# TELEMETRY: sound_grenade detonation (pos, magnitude)
			MatchStats.log_event("sound_grenade", {
				"x": _flight_target.x, "y": _flight_target.y,
				"mag": GRENADE_NOISE,
			})
			queue_redraw()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	var band: int = _tick_morale(delta)
	if current_command == Command.FLEE:
		_follow_navigation()
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
			# Arrived: release a pending approach-throw if now in range.
			if _has_pending_throw:
				_has_pending_throw = false
				if global_position.distance_to(_pending_throw_pos) <= THROW_RANGE_PX:
					_launch_grenade(_pending_throw_pos)
		return
	# IDLE: unarmed — back away from threats.
	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null and band != MoraleBand.BROKEN:
		_kite_from(threat, KITE_SPEED)
	else:
		velocity = Vector2.ZERO


func get_status_text() -> String:
	if _grenade_in_flight:
		return "Grenade in flight"
	if _grenade_cooldown > 0.0:
		return "Rearming (%ds)" % int(ceil(_grenade_cooldown))
	return "Sound grenade ready"


func _draw() -> void:
	super._draw()
	if use_sprite and not _grenade_in_flight:
		return
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	if not use_sprite:
		# Support marker: amber spark dot (procedural-era legibility, §10.5).
		var s: float = float(size_px) / 22.0
		draw_circle(Vector2(0, -10.0 * s), 2.4 * s, Color(0.85, 0.65, 0.25))
	# Flight telegraph: dashed amber line to the landing point (render-only).
	if _grenade_in_flight:
		var to_target: Vector2 = IsoView.world_to_screen(_flight_target) - IsoView.world_to_screen(position)
		draw_line(Vector2.ZERO, to_target, Color(0.85, 0.65, 0.25, 0.5), 1.0)
		draw_arc(to_target, 8.0, 0.0, TAU, 12, Color(0.85, 0.65, 0.25, 0.7), 1.0)
