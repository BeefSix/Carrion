extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 213.0
const ATTACK_DAMAGE := 12
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 10.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	var threat = _find_nearest_threat_in_range(KITE_RANGE)
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
			_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise()


func _find_nearest_zombie():
	var best = null
	var best_dist := ATTACK_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction != Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _find_nearest_threat_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction != Faction.ZOMBIE:
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


func _emit_shot_noise() -> void:
	var nf := get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, NOISE_PER_SHOT)
