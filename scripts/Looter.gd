class_name Looter
extends "res://scripts/Unit.gd"

enum Sub { NONE, HUNT_APPROACH, HUNT_FIRE, POST_KILL_SEARCH, RETURN_HOME, GATHER_APPROACH, GATHER_CHANNEL, GATHER_RETURN }

const MAGNUM_DAMAGE := 22
const MAGNUM_PERIOD := 2.5
const MAGNUM_RANGE := 128.0
const MAGNUM_NOISE := 20.0
const HUNT_VISION := 384.0
const SALVAGE_PER_KILL := 12
const SALVAGE_PER_LOOT_TRIP := 25
const CHANNEL_TIME := 3.0
const INTERACTION_RANGE := 48.0
const AVOID_RANGE := 160.0
const RETARGET_INTERVAL := 0.3
const POST_KILL_SEARCH_DURATION := 6.0
const POST_KILL_SEARCH_RADIUS := 150.0
const POST_KILL_WANDER_INTERVAL := 1.5

var _sub: Sub = Sub.NONE
var _target_zombie = null
var _target_lootable = null
var _home_base = null
var _carrying := 0
var _attack_cooldown := 0.0
var _channel_timer := 0.0
var _retarget_timer := 0.0

var _search_kill_pos: Vector2 = Vector2.ZERO
var _search_timer := 0.0
var _search_wander_timer := 0.0


func gather_from(lootable) -> void:
	if lootable == null or not is_instance_valid(lootable):
		return
	_target_lootable = lootable
	_target_zombie = null
	_sub = Sub.GATHER_APPROACH
	current_command = Command.GATHER
	_nav.target_position = lootable.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_cancel_auto()


func _cancel_auto() -> void:
	_sub = Sub.NONE
	_target_zombie = null
	_target_lootable = null


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer = max(0.0, _retarget_timer - delta)

	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		if _carrying > 0:
			_start_return_home()
		else:
			_try_start_auto_hunt()

	match _sub:
		Sub.HUNT_APPROACH:
			_tick_hunt_approach()
		Sub.HUNT_FIRE:
			_tick_hunt_fire(delta)
		Sub.POST_KILL_SEARCH:
			_tick_post_kill_search(delta)
		Sub.RETURN_HOME:
			_tick_return_home()
		Sub.GATHER_APPROACH:
			_tick_gather_approach()
		Sub.GATHER_CHANNEL:
			_tick_gather_channel(delta)
		Sub.GATHER_RETURN:
			_tick_gather_return()
		_:
			velocity = Vector2.ZERO


func _try_start_auto_hunt() -> void:
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z == null:
		velocity = Vector2.ZERO
		return
	_target_zombie = z
	_sub = Sub.HUNT_APPROACH
	_nav.target_position = z.global_position


func _start_return_home() -> void:
	_home_base = _find_nearest_command_post()
	if _home_base == null:
		velocity = Vector2.ZERO
		return
	_sub = Sub.RETURN_HOME
	_nav.target_position = _home_base.position


func _tick_hunt_approach() -> void:
	if _target_zombie == null or not is_instance_valid(_target_zombie):
		_sub = Sub.NONE
		return
	var dist := global_position.distance_to(_target_zombie.global_position)
	if dist <= MAGNUM_RANGE:
		_sub = Sub.HUNT_FIRE
		velocity = Vector2.ZERO
		return
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_nav.target_position = _target_zombie.global_position
	_follow_navigation()


func _tick_hunt_fire(_delta: float) -> void:
	if _target_zombie == null or not is_instance_valid(_target_zombie):
		_sub = Sub.NONE
		return
	velocity = Vector2.ZERO
	var dist := global_position.distance_to(_target_zombie.global_position)
	if dist > MAGNUM_RANGE * 1.2:
		_sub = Sub.HUNT_APPROACH
		return
	if _attack_cooldown <= 0.0:
		_attack_cooldown = MAGNUM_PERIOD
		_emit_magnum_noise()
		var was_alive: bool = _target_zombie.current_hp > 0
		_target_zombie.take_damage(MAGNUM_DAMAGE, self)
		if was_alive and (not is_instance_valid(_target_zombie) or _target_zombie.current_hp <= 0):
			_carrying += SALVAGE_PER_KILL
			_search_kill_pos = global_position
			_search_timer = POST_KILL_SEARCH_DURATION
			_search_wander_timer = 0.0
			_target_zombie = null
			_sub = Sub.POST_KILL_SEARCH


func _tick_post_kill_search(delta: float) -> void:
	_search_timer -= delta
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z != null:
		_target_zombie = z
		_sub = Sub.HUNT_APPROACH
		_nav.target_position = z.global_position
		return
	if _search_timer <= 0.0:
		_sub = Sub.NONE
		return
	_search_wander_timer -= delta
	if _search_wander_timer <= 0.0:
		_search_wander_timer = POST_KILL_WANDER_INTERVAL
		var offset := Vector2(randf_range(-POST_KILL_SEARCH_RADIUS, POST_KILL_SEARCH_RADIUS), randf_range(-POST_KILL_SEARCH_RADIUS, POST_KILL_SEARCH_RADIUS))
		var target: Vector2 = _search_kill_pos + offset
		target.x = clamp(target.x, 50.0, 2510.0)
		target.y = clamp(target.y, 50.0, 2510.0)
		_nav.target_position = target
	if not _nav.is_navigation_finished():
		_follow_navigation()
	else:
		velocity = Vector2.ZERO


func _tick_return_home() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_command_post()
		if _home_base == null:
			_sub = Sub.NONE
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		_deposit_at_home()
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_avoidant_move_to(_home_base.position)


func _tick_gather_approach() -> void:
	if _target_lootable == null or not is_instance_valid(_target_lootable):
		_sub = Sub.NONE
		current_command = Command.IDLE
		return
	if global_position.distance_to(_target_lootable.position) <= INTERACTION_RANGE:
		_sub = Sub.GATHER_CHANNEL
		_channel_timer = CHANNEL_TIME
		velocity = Vector2.ZERO
	else:
		_follow_navigation()


func _tick_gather_channel(delta: float) -> void:
	velocity = Vector2.ZERO
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		if _target_lootable != null and is_instance_valid(_target_lootable) and _target_lootable.has_method("take_salvage"):
			var taken: int = _target_lootable.take_salvage(SALVAGE_PER_LOOT_TRIP)
			_carrying += taken
			var nf := get_tree().get_first_node_in_group("noise_field")
			if nf != null:
				nf.add_noise(global_position, 25.0)
		_home_base = _find_nearest_command_post()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_sub = Sub.GATHER_RETURN
		_nav.target_position = _home_base.position


func _tick_gather_return() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_command_post()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		_deposit_at_home()
		if _target_lootable != null and is_instance_valid(_target_lootable) and _target_lootable.remaining_salvage > 0:
			_sub = Sub.GATHER_APPROACH
			_nav.target_position = _target_lootable.position
		else:
			_sub = Sub.NONE
			current_command = Command.IDLE
	else:
		_avoidant_move_to(_home_base.position)


func _deposit_at_home() -> void:
	if _carrying > 0:
		GameState.add_salvage(_carrying)
	_carrying = 0


func _avoidant_move_to(target_pos: Vector2) -> void:
	var to_target: Vector2 = (target_pos - global_position).normalized()
	var threat = _find_nearest_zombie_in_range(AVOID_RANGE)
	if threat != null:
		var away: Vector2 = (global_position - threat.global_position).normalized()
		velocity = (to_target + away * 1.5).normalized() * move_speed
	else:
		velocity = to_target * move_speed
	move_and_slide()


func _find_nearest_zombie_in_range(range_px: float):
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
	return best


func _find_nearest_command_post():
	var nearest = null
	var nearest_dist := INF
	for cp in get_tree().get_nodes_in_group("command_post"):
		var dist: float = global_position.distance_to(cp.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cp
	return nearest


func _emit_magnum_noise() -> void:
	var nf := get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, MAGNUM_NOISE)
