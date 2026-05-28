class_name Looter
extends "res://scripts/Unit.gd"

enum Sub {
	NONE,
	HUNT_APPROACH,
	HUNT_FIRE,
	RETURN_HOME,
	RETURN_TO_HUNT,
	SEARCH,
}

const MAGNUM_DAMAGE := 22
const MAGNUM_PERIOD := 2.5
const MAGNUM_RANGE := 128.0
const MAGNUM_NOISE := 20.0
const HUNT_VISION := 384.0
const SALVAGE_PER_KILL := 25
const CARRY_CAP := 25
const INTERACTION_RANGE := 80.0
const KILL_AREA_ARRIVE_RANGE := 80.0
const AVOID_RANGE := 160.0
const RETARGET_INTERVAL := 0.3
const SEARCH_DURATION := 6.0
const SEARCH_RADIUS := 150.0
const SEARCH_WANDER_INTERVAL := 1.5

var _sub: Sub = Sub.NONE
var _target_zombie = null
var _home_base = null
var _carrying := 0
var _attack_cooldown := 0.0
var _retarget_timer := 0.0

var _last_kill_pos: Vector2 = Vector2.ZERO
var _search_timer := 0.0
var _search_wander_timer := 0.0


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	# Preserve _last_kill_pos so the cycle resumes after the manual detour.
	_sub = Sub.NONE
	_target_zombie = null


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer = max(0.0, _retarget_timer - delta)

	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		_pick_next_action()

	match _sub:
		Sub.HUNT_APPROACH:
			_tick_hunt_approach()
		Sub.HUNT_FIRE:
			_tick_hunt_fire()
		Sub.RETURN_HOME:
			_tick_return_home()
		Sub.RETURN_TO_HUNT:
			_tick_return_to_hunt()
		Sub.SEARCH:
			_tick_search(delta)
		_:
			velocity = Vector2.ZERO


func _pick_next_action() -> void:
	if _carrying > 0:
		_start_return_home()
		return
	if _last_kill_pos != Vector2.ZERO:
		_start_return_to_hunt()
		return
	_try_start_auto_hunt()


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


func _start_return_to_hunt() -> void:
	if global_position.distance_to(_last_kill_pos) <= KILL_AREA_ARRIVE_RANGE:
		_enter_search()
		return
	_sub = Sub.RETURN_TO_HUNT
	_nav.target_position = _last_kill_pos


func _enter_search() -> void:
	_sub = Sub.SEARCH
	_search_timer = SEARCH_DURATION
	_search_wander_timer = 0.0


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


func _tick_hunt_fire() -> void:
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
		_target_zombie.take_damage(get_effective_damage(MAGNUM_DAMAGE), self)
		if was_alive and (not is_instance_valid(_target_zombie) or _target_zombie.current_hp <= 0):
			_carrying = min(_carrying + SALVAGE_PER_KILL, CARRY_CAP)
			_last_kill_pos = global_position
			_target_zombie = null
			# Carry cap forces immediate return — no lingering after kill.
			_start_return_home()


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
	_try_defensive_fire()
	_avoidant_move_to(_home_base.position)


func _try_defensive_fire() -> void:
	if _attack_cooldown > 0.0:
		return
	var z = _find_nearest_zombie_in_range(MAGNUM_RANGE)
	if z == null:
		return
	_attack_cooldown = MAGNUM_PERIOD
	_emit_magnum_noise()
	# Defensive kills don't increase carry — already at cap.
	z.take_damage(get_effective_damage(MAGNUM_DAMAGE), self)


func _tick_return_to_hunt() -> void:
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z != null:
		_target_zombie = z
		_sub = Sub.HUNT_APPROACH
		_nav.target_position = z.global_position
		return
	if global_position.distance_to(_last_kill_pos) <= KILL_AREA_ARRIVE_RANGE:
		_enter_search()
		return
	_follow_navigation()


func _tick_search(delta: float) -> void:
	_search_timer -= delta
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z != null:
		_target_zombie = z
		_sub = Sub.HUNT_APPROACH
		_nav.target_position = z.global_position
		return
	if _search_timer <= 0.0:
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_search_wander_timer -= delta
	if _search_wander_timer <= 0.0:
		_search_wander_timer = SEARCH_WANDER_INTERVAL
		var offset := Vector2(randf_range(-SEARCH_RADIUS, SEARCH_RADIUS), randf_range(-SEARCH_RADIUS, SEARCH_RADIUS))
		var t: Vector2 = _last_kill_pos + offset
		t.x = clamp(t.x, 50.0, 6094.0)
		t.y = clamp(t.y, 50.0, 6094.0)
		_nav.target_position = t
	if not _nav.is_navigation_finished():
		_follow_navigation()
	else:
		velocity = Vector2.ZERO


func _deposit_at_home() -> void:
	if _carrying > 0:
		if is_in_group("ai_units"):
			var ai = get_tree().get_first_node_in_group("ai_controller")
			if ai != null and ai.has_method("add_salvage"):
				ai.add_salvage(_carrying)
		else:
			GameState.add_salvage(_carrying)
	_carrying = 0


func _avoidant_move_to(target_pos: Vector2) -> void:
	var to_target: Vector2 = (target_pos - global_position).normalized()
	var threat = _find_nearest_zombie_in_range(AVOID_RANGE)
	var spd: float = get_effective_move_speed()
	if threat != null:
		var away: Vector2 = (global_position - threat.global_position).normalized()
		velocity = (to_target + away * 1.5).normalized() * spd
	else:
		velocity = to_target * spd
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
