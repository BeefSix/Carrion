class_name Looter
extends "res://scripts/Unit.gd"

enum GatherState { NONE, APPROACH_LOOTABLE, CHANNELING, RETURN_HOME, DEPOSIT }

const CHANNEL_TIME := 3.0
const SALVAGE_PER_TRIP := 25
const INTERACTION_RANGE := 48.0

var _gather_state: int = GatherState.NONE
var _target_lootable = null
var _home_base = null
var _channel_timer := 0.0
var _carrying := 0


func gather_from(lootable) -> void:
	if lootable == null or not is_instance_valid(lootable):
		return
	_target_lootable = lootable
	_carrying = 0
	_gather_state = GatherState.APPROACH_LOOTABLE
	current_command = Command.GATHER
	_nav.target_position = lootable.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_stop_gather()


func _stop_gather() -> void:
	_gather_state = GatherState.NONE
	_target_lootable = null
	_home_base = null
	_channel_timer = 0.0


func _find_nearest_command_post():
	var nearest = null
	var nearest_dist := INF
	for cp in get_tree().get_nodes_in_group("command_post"):
		var dist: float = global_position.distance_to(cp.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cp
	return nearest


func _physics_process(delta: float) -> void:
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return
	if current_command != Command.GATHER:
		return

	match _gather_state:
		GatherState.APPROACH_LOOTABLE:
			if _target_lootable == null or not is_instance_valid(_target_lootable):
				_stop_gather()
				current_command = Command.IDLE
				return
			if global_position.distance_to(_target_lootable.position) <= INTERACTION_RANGE:
				_gather_state = GatherState.CHANNELING
				_channel_timer = CHANNEL_TIME
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		GatherState.CHANNELING:
			_channel_timer -= delta
			if _channel_timer <= 0:
				_finish_channel()
		GatherState.RETURN_HOME:
			if _home_base == null or not is_instance_valid(_home_base):
				_home_base = _find_nearest_command_post()
				if _home_base == null:
					_stop_gather()
					current_command = Command.IDLE
					return
				_nav.target_position = _home_base.position
			if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
				_deposit_and_continue()
			else:
				_follow_navigation()
		GatherState.DEPOSIT:
			# Single-frame transitional state; deposit happens in _deposit_and_continue
			pass


func _finish_channel() -> void:
	if _target_lootable != null and is_instance_valid(_target_lootable) and _target_lootable.has_method("take_salvage"):
		_carrying = _target_lootable.take_salvage(SALVAGE_PER_TRIP)
		var nf := get_tree().get_first_node_in_group("noise_field")
		if nf != null:
			nf.add_noise(global_position, 25.0)
	else:
		_carrying = 0
	_home_base = _find_nearest_command_post()
	if _home_base == null:
		_stop_gather()
		current_command = Command.IDLE
		return
	_gather_state = GatherState.RETURN_HOME
	_nav.target_position = _home_base.position


func _deposit_and_continue() -> void:
	if _carrying > 0:
		GameState.add_salvage(_carrying)
	_carrying = 0
	if _target_lootable != null and is_instance_valid(_target_lootable) and _target_lootable.remaining_salvage > 0:
		_gather_state = GatherState.APPROACH_LOOTABLE
		_nav.target_position = _target_lootable.position
	else:
		_stop_gather()
		current_command = Command.IDLE
