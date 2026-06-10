extends "res://scripts/CombatUnit.gd"

# Survivor Bolter (DESIGN_MASTER §7.3, v1) — the faction's basic ranged
# unit: an improvised crossbow, SILENT by design. Where the Rifleman buys
# damage with noise, the Bolter's whole identity is that firing does not
# feed the ecosystem: no NoiseBus emission per shot (deliberate, per the
# CLAUDE.md noise-profile rule — Survivor is the silent faction; do not
# add an emission here casually). The price is tempo: long reload.
#
# NOT CONNECTED YET (2026-06-10): no producer references Bolter.tscn and
# the Survivor faction picker is unchanged. Connection point: a
# SettlementHub/garrison production row + AIProfiles SURVIVOR entry.
# Doctrines (Longbolt / Pinbolt) are [PROPOSED] — deferred.

const ATTACK_RANGE := 220.0       # a touch past Rifleman: deliberate shots
const ATTACK_DAMAGE := 14
const ATTACK_PERIOD := 1.6        # slow reload — the silence tax
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

const PROJECTILE_COLOR := Color(0.82, 0.78, 0.66)  # pale bone-wood bolt
const BASE_ACCURACY_DEG := 3.0    # tighter than rifle spray: aimed shots

const THREAT_CHECK_INTERVAL := 0.2
var _threat_check_timer: float = 0.0
var _threat_cached = null

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0

const SPRITE_ROOT := "res://assets/sprites/units/survivor/bolter/"
const ATTACK_ANIM_HOLD := 0.4


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _ready() -> void:
	super._ready()
	_init_sprite()


func _morale_enabled() -> bool:
	return true


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	var band: int = _tick_morale(delta)
	if current_command == Command.FLEE:
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
			# SILENT: no _emit_shot_noise. This absence is the unit.


func _try_shoot_in_range(delta: float) -> void:
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
		# SILENT: no shot noise (see above).


func _fire_at(target) -> void:
	_attack_anim_timer = ATTACK_ANIM_HOLD
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus) * _suppression_spread_multiplier() * _morale_spread_mult()
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": move_speed * 4.5,  # bolts fly flat and fast
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BOLT,
		"color": PROJECTILE_COLOR,
		"visual_width": 2.0,
	})
