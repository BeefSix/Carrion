extends "res://scripts/Unit.gd"

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

	var threat = _find_nearest_threat_in_range(KITE_RANGE)
	if threat != null:
		_kite_from(threat)
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_enemy()
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise()


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: keep the nav target, fire opportunistically at any
	# hostile (humans only - Hunters ignore zombies per the targeting filter).
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_enemy()
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD
		_emit_shot_noise()


func _fire_at(target) -> void:
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus)
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
		"visual_length": 20.0,
		"visual_width": 2.0,
	})


# Tribal Hunters fight survivors and military, NOT zombies.
# Zombies ignore tribal units per the faction filter in Shambler._update_target,
# so there's no reason for Hunters to engage them either. The Tribal strategic
# identity is "let the zombies be; hunt the humans."
func _find_nearest_enemy():
	var best = null
	var best_dist := ATTACK_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == Faction.TRIBAL or u.faction == Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(ATTACK_RANGE)


func _find_nearest_hostile_hq(range_px: float):
	# Opposing HQ targeting for the win condition. Tribal Hunter sees Military and
	# Survivor HQs as hostile - the same anti-human bent the unit-target filter uses.
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
		if u.faction == Faction.TRIBAL or u.faction == Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _kite_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * KITE_SPEED
	move_and_slide()


func _emit_shot_noise() -> void:
	var nf := get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, NOISE_PER_SHOT)
