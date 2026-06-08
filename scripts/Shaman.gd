extends "res://scripts/Unit.gd"

enum Sub { NONE, APPROACH, CHANNEL }

const FORCE_SPAWN_COST := 25
const FORCE_SPAWN_CHANNEL_TIME := 5.0
const FORCE_SPAWN_COUNT := 4
const INTERACTION_RANGE := 80.0
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")

var _sub: Sub = Sub.NONE
var _target_building = null
var _channel_timer := 0.0


func force_spawn_at(building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not (building.is_in_group("lootable") and building.is_infested):
		return
	_target_building = building
	_sub = Sub.APPROACH
	current_command = Command.GATHER
	_nav.target_position = building.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_cancel()


func _cancel() -> void:
	_sub = Sub.NONE
	_target_building = null
	_channel_timer = 0.0


func _physics_process(delta: float) -> void:
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		velocity = Vector2.ZERO
		return

	if _target_building == null or not is_instance_valid(_target_building):
		_cancel()
		current_command = Command.IDLE
		return

	match _sub:
		Sub.APPROACH:
			if global_position.distance_to(_target_building.position) <= INTERACTION_RANGE:
				_sub = Sub.CHANNEL
				_channel_timer = FORCE_SPAWN_CHANNEL_TIME
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		Sub.CHANNEL:
			velocity = Vector2.ZERO
			_channel_timer -= delta
			if _channel_timer <= 0.0:
				_execute_force_spawn()


func _execute_force_spawn() -> void:
	# Owner-aware affordability + spend. An AI-spawned Shaman debits its
	# AIController's pool; a human-player Shaman debits GameState. Pre-fix
	# this hardcoded GameState, which would have drained the human player's
	# pool if the AI ever ran Tribal (currently AI is Military-only, but
	# the hardcoded path was a latent bug per AUDIT M).
	if not can_spend_salvage(FORCE_SPAWN_COST):
		_cancel()
		current_command = Command.IDLE
		return
	if _target_building == null or not is_instance_valid(_target_building):
		_cancel()
		current_command = Command.IDLE
		return
	spend_salvage(FORCE_SPAWN_COST)
	var center: Vector2 = _target_building.position
	for i in range(FORCE_SPAWN_COUNT):
		var jitter := Vector2(randf_range(-32, 32), randf_range(-32, 32))
		var s = SHAMBLER_SCENE.instantiate()
		s.position = center + jitter
		if "is_tribal_aligned" in s:
			s.is_tribal_aligned = true
		get_parent().add_child(s)
	_cancel()
	current_command = Command.IDLE


func get_status_text_for_hud() -> String:
	match _sub:
		Sub.APPROACH:
			return "Approaching ritual target..."
		Sub.CHANNEL:
			return "Channeling ritual... %.1fs" % _channel_timer
		_:
			return ""
