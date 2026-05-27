extends "res://scripts/Unit.gd"

enum ZombieState { IDLE, INVESTIGATE, CHASE, ATTACK }

const VISION_RANGE := 384.0
const ATTACK_RANGE := 36.0
const LOST_TARGET_RANGE := 576.0
const ATTACK_DAMAGE := 8
const ATTACK_PERIOD := 1.0
const RETARGET_INTERVAL := 0.3
const INVESTIGATE_ARRIVE_RANGE := 60.0

var _zombie_state: int = ZombieState.IDLE
var _target = null
var _investigate_target: Vector2 = Vector2.ZERO
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func investigate(world_pos: Vector2) -> void:
	_investigate_target = world_pos
	_zombie_state = ZombieState.INVESTIGATE
	_nav.target_position = world_pos


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_update_target()
		if _target != null and _zombie_state == ZombieState.CHASE:
			_nav.target_position = _target.global_position

	match _zombie_state:
		ZombieState.IDLE:
			velocity = Vector2.ZERO
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
		ZombieState.INVESTIGATE:
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
			elif global_position.distance_to(_investigate_target) <= INVESTIGATE_ARRIVE_RANGE:
				_zombie_state = ZombieState.IDLE
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		ZombieState.CHASE:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			var dist := global_position.distance_to(_target.global_position)
			if dist <= ATTACK_RANGE:
				_zombie_state = ZombieState.ATTACK
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		ZombieState.ATTACK:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			var dist := global_position.distance_to(_target.global_position)
			if dist > ATTACK_RANGE * 1.2:
				_zombie_state = ZombieState.CHASE
				return
			velocity = Vector2.ZERO
			if _attack_cooldown <= 0:
				if _target.has_method("take_damage"):
					_target.take_damage(ATTACK_DAMAGE)
				_attack_cooldown = ATTACK_PERIOD


func _update_target() -> void:
	var best = null
	var best_dist := VISION_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == Faction.ZOMBIE or u.faction == Faction.TRIBAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	_target = best
