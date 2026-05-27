extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 160.0
const ATTACK_PERIOD := 0.5
const ATTACK_DAMAGE := 18
const AOE_RADIUS := 40.0
const NOISE_PER_SHOT := 25.0
const RETARGET_INTERVAL := 0.3

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return
	velocity = Vector2.ZERO
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_aoe(_target.global_position)
			_attack_cooldown = ATTACK_PERIOD


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


func _fire_aoe(center: Vector2) -> void:
	var nf := get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, NOISE_PER_SHOT)
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.faction != Faction.ZOMBIE:
			continue
		if u.global_position.distance_to(center) <= AOE_RADIUS:
			u.take_damage(ATTACK_DAMAGE, self)
