extends "res://scripts/CombatUnit.gd"

const ATTACK_RANGE := 224.0
const ATTACK_DAMAGE := 14
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 1.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

# Projectile config: dark organic-toned arrow per Tribal faction identity.
# Slower than Military per the design doc's 0.4-0.7s arrow flight target.
const PROJECTILE_SPEED := 500.0
const PROJECTILE_COLOR := Color(0.45, 0.35, 0.22)
# Tighter cone than Rifleman: Hunter is a deliberate aimed shooter.
const BASE_ACCURACY_DEG := 3.0

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
# Threat-scan cache - 5Hz polling instead of per-frame.
const THREAT_CHECK_INTERVAL := 0.2
var _threat_check_timer: float = 0.0
var _threat_cached = null


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.CREMATE:
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
	# Attack-while-moving: keep the nav target, fire opportunistically at any
	# hostile (humans only - the _should_skip_target override below excludes
	# ZOMBIE faction).
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
	# Damage resolves at impact via CombatUnit.resolve_damage in Projectile.gd.
	# Suppression widens the cone at the shooter's position (DESIGN_MASTER §7.1).
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus) * _suppression_spread_multiplier()
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": PROJECTILE_SPEED,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.ARROW,
		"color": PROJECTILE_COLOR,
		"visual_length": 16.0,
		"visual_width": 1.8,
	})


# Tribal Hunters fight survivors and military, NOT zombies. The substrate's
# _find_nearest_hostile / _find_nearest_threat_in_range route through this
# hook so the zombie-exemption Tribal-design quirk lives in ONE place on
# top of the shared targeting/threat logic.
func _should_skip_target(u) -> bool:
	return u != null and "faction" in u and u.faction == GameState.Faction.ZOMBIE
