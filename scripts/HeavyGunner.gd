extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 160.0
const ATTACK_PERIOD := 0.5
const ATTACK_DAMAGE := 18
const AOE_RADIUS := 40.0
const NOISE_PER_SHOT := 25.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 80.0
const KITE_SPEED := 25.0

# Projectile config: bright yellow bullet, slightly bigger than Rifleman.
# Speed is 2x move_speed (set at fire time). HG at 64 move_speed -> 128 px/s.
# AOE damage at impact preserves the previous instant-AOE behavior.
const PROJECTILE_COLOR := Color(1.0, 0.82, 0.35)
# Wider cone than Rifleman: HG is sustained-fire, less aimed.
const BASE_ACCURACY_DEG := 8.0

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
		_kite_from(threat)
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: fire opportunistically at hostiles within
	# ATTACK_RANGE. No kiting (honor move order). Cooldown shared with idle path.
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD


func _fire_at(target) -> void:
	# Noise fires at fire-time (per the projectile design doc). Damage is
	# deferred to projectile impact - area_radius > 0 routes through the
	# Projectile's AOE handler.
	NoiseBus.emit(global_position, NOISE_PER_SHOT)
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus)
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": move_speed * 4.0,
		"firer": self,
		"faction": faction,
		"area_radius": AOE_RADIUS,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 3.0,  # bullet radius in px (slightly bigger than Rifleman)
	})


func _find_nearest_zombie():
	# Routed through GameState.is_hostile (AUDIT H4) - the previous faction-
	# equality skip broke the Military mirror by dropping same-faction enemies.
	# Falls back to opposing HQ when no hostile unit is in range.
	var best = null
	var best_dist := ATTACK_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(ATTACK_RANGE)


func _find_nearest_hostile_hq(range_px: float):
	var enemy_group: String = "player_buildings" if is_in_group("ai_units") else "ai_buildings"
	var best = null
	var best_dist := range_px
	for b in get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(b):
			continue
		if not b.is_in_group("hq"):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d <= best_dist:
			best_dist = d
			best = b
	return best


func _find_nearest_threat_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d <= best_dist:
			best_dist = d
			best = c
	return best


func _kite_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * KITE_SPEED
	move_and_slide()


