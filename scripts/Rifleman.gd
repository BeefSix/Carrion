extends "res://scripts/CombatUnit.gd"

const ATTACK_RANGE := 213.0
const ATTACK_DAMAGE := 12
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 10.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

# Projectile config: small yellow bullet. Speed is 2x the firer's move_speed
# (computed at fire time) so each bullet visibly outpaces the shooter but
# stays slow enough to track. Rifleman at 80 move_speed -> 160 px/s bullets.
const PROJECTILE_COLOR := Color(0.95, 0.78, 0.35)
# Base accuracy in degrees. Lower = tighter cone. Squad accuracy bonus (from
# leadership aura) reduces effective spread multiplicatively:
# effective_spread = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus).
const BASE_ACCURACY_DEG := 4.0

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
# Threat-scan cache. Was previously per-frame (60 Hz) via
# _find_nearest_threat_in_range, iterating units + corpses groups for every
# combat unit in IDLE state. At 30 idle units + 200 zombies that's ~360K
# iterations/sec just for kite-from-threat detection. 5 Hz polling preserves
# the gameplay behavior - kite reaction within 0.2s is plenty.
const THREAT_CHECK_INTERVAL := 0.2
var _threat_check_timer: float = 0.0
var _threat_cached = null

# Sprite root and attack-anim hold. Substrate lives in CombatUnit (sprite
# building, direction picking, animation playback); this subclass just
# names its asset directory and the hold duration after firing.
const SPRITE_ROOT := "res://assets/sprites/units/military/rifleman/"
const ATTACK_ANIM_HOLD := 0.35


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _ready() -> void:
	super._ready()
	_init_sprite()


func _morale_enabled() -> bool:
	return true


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	# Morale tick (DESIGN_MASTER §5.1). Refreshes the cached band used by the
	# branches below; FLEE state is entered by CombatUnit._on_morale_band_changed.
	var band: int = _tick_morale(delta)
	if current_command == Command.FLEE:
		# BROKEN: walk to the flee target, no firing. Recovery clears
		# current_command back to IDLE inside _on_morale_band_changed.
		if not _follow_navigation():
			velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		elif stance == Stance.AGGRESSIVE:
			_try_shoot_in_range(delta)
		return

	if stance == Stance.PASSIVE:
		velocity = Vector2.ZERO
		return

	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null:
		_kite_from(threat, KITE_SPEED)
	elif band == MoraleBand.SHAKEN and _morale_should_fear_step():
		# SHAKEN with no immediate kite target: fear-step away from the
		# nearest in-range zombie at FEAR_STEP_SPEED. Produces the visible
		# back-step-while-firing tell the spec calls for. HOTHEAD's profile
		# returns false from _morale_should_fear_step so this branch skips.
		var fear_threat = _find_nearest_threat_in_range(ATTACK_RANGE)
		if fear_threat != null:
			_kite_from(fear_threat, FEAR_STEP_SPEED)
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile(ATTACK_RANGE)
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise(NOISE_PER_SHOT)


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: keep the nav target, but fire opportunistically at
	# anything in ATTACK_RANGE. No kiting (we honor the move order). Reuses the
	# same cooldown/retarget cadence as the idle attack path.
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile(ATTACK_RANGE)
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD
		_emit_shot_noise(NOISE_PER_SHOT)


func _fire_at(target) -> void:
	# Spawns a direct-fire projectile. Damage resolves on IMPACT (in
	# Projectile.gd -> CombatUnit.resolve_damage), not here. Noise fires at
	# the call site per the projectile spec. The neutral counter matrix in
	# this batch means impact-time resolution returns the same value the
	# pre-substrate path produced.
	_attack_anim_timer = ATTACK_ANIM_HOLD
	# Spread stack: base * (squad accuracy aura) * (suppression at position) *
	# (morale band - SHAKEN widens by 1.5x). Order is multiplicative so each
	# system tunes independently. DESIGN_MASTER §7.1 (suppression) + §5.1 (morale).
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus) * _suppression_spread_multiplier() * _morale_spread_mult()
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": move_speed * 4.0,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 2.5,  # bullet radius in px
	})
