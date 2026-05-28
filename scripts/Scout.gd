extends "res://scripts/Unit.gd"

enum Sub { NONE, GATHER_APPROACH, GATHER_CHANNEL, GATHER_RETURN }
enum EnergyState { NORMAL, BURST, FATIGUE, COOLDOWN }

const SALVAGE_PER_CHANNEL := 25
const CARRY_CAP := 100
const CHANNEL_TIME := 3.0
const INTERACTION_RANGE := 80.0
const SEARCH_RADIUS := 1500.0
const LOOT_NOISE := 1.0

const BURST_DURATION := 5.0
const BURST_MULT := 1.8
const FATIGUE_DURATION := 2.0
const FATIGUE_MULT := 0.7
const COOLDOWN_DURATION := 4.0
const ZOMBIE_DETECT_RANGE := 256.0

const NORMAL_COLOR := Color("7a5c3c")
const BURST_COLOR := Color("c89060")
const FATIGUE_COLOR := Color("4a3a26")

var _sub: Sub = Sub.NONE
var _target_lootable = null
var _home_base = null
var _carrying := 0
var _channel_timer := 0.0
var _energy_state: EnergyState = EnergyState.NORMAL
var _energy_timer := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("scouts")


func gather_from(lootable) -> void:
	if lootable == null or not is_instance_valid(lootable):
		return
	_target_lootable = lootable
	_sub = Sub.GATHER_APPROACH
	current_command = Command.GATHER
	_nav.target_position = lootable.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_sub = Sub.NONE
	_target_lootable = null


func get_effective_move_speed() -> float:
	return move_speed * speed_mult * _get_energy_mult()


func get_energy_state() -> int:
	return _energy_state


func _get_energy_mult() -> float:
	match _energy_state:
		EnergyState.BURST:
			return BURST_MULT
		EnergyState.FATIGUE:
			return FATIGUE_MULT
		_:
			return 1.0


func _physics_process(delta: float) -> void:
	_update_energy(delta)

	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		if _carrying >= CARRY_CAP:
			_start_return_home()
		else:
			_try_find_lootable()

	match _sub:
		Sub.GATHER_APPROACH:
			_tick_gather_approach()
		Sub.GATHER_CHANNEL:
			_tick_gather_channel(delta)
		Sub.GATHER_RETURN:
			_tick_gather_return()
		_:
			velocity = Vector2.ZERO


func _update_energy(delta: float) -> void:
	if _energy_timer > 0:
		_energy_timer -= delta
		if _energy_timer <= 0:
			_transition_energy_state()
	if _energy_state == EnergyState.NORMAL:
		if _zombie_within_detect_range():
			_set_energy_state(EnergyState.BURST, BURST_DURATION)


func _transition_energy_state() -> void:
	match _energy_state:
		EnergyState.BURST:
			_set_energy_state(EnergyState.FATIGUE, FATIGUE_DURATION)
		EnergyState.FATIGUE:
			_set_energy_state(EnergyState.COOLDOWN, COOLDOWN_DURATION)
		EnergyState.COOLDOWN:
			_set_energy_state(EnergyState.NORMAL, 0.0)


func _set_energy_state(new_state: EnergyState, duration: float) -> void:
	_energy_state = new_state
	_energy_timer = duration
	match new_state:
		EnergyState.BURST:
			body_color = BURST_COLOR
		EnergyState.FATIGUE:
			body_color = FATIGUE_COLOR
		_:
			body_color = NORMAL_COLOR
	queue_redraw()


func _zombie_within_detect_range() -> bool:
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction != Faction.ZOMBIE:
			continue
		if global_position.distance_to(u.global_position) <= ZOMBIE_DETECT_RANGE:
			return true
	return false


func _try_find_lootable() -> void:
	var best = null
	var best_dist := SEARCH_RADIUS
	for l in get_tree().get_nodes_in_group("lootable"):
		if not is_instance_valid(l):
			continue
		if l.remaining_salvage <= 0:
			continue
		var d: float = global_position.distance_to(l.position)
		if d <= best_dist:
			best_dist = d
			best = l
	if best == null:
		velocity = Vector2.ZERO
		return
	_target_lootable = best
	_sub = Sub.GATHER_APPROACH
	_nav.target_position = best.position


func _start_return_home() -> void:
	var depot = _find_nearest_depot()
	if depot == null:
		velocity = Vector2.ZERO
		return
	_home_base = depot
	_sub = Sub.GATHER_RETURN
	_nav.target_position = depot.position


func _tick_gather_approach() -> void:
	if _target_lootable == null or not is_instance_valid(_target_lootable):
		_sub = Sub.NONE
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
			var room: int = CARRY_CAP - _carrying
			var amount: int = min(SALVAGE_PER_CHANNEL, room)
			_carrying += _target_lootable.take_salvage(amount)
			var nf := get_tree().get_first_node_in_group("noise_field")
			if nf != null:
				nf.add_noise(global_position, LOOT_NOISE)
		if _carrying >= CARRY_CAP:
			_start_return_home()
		else:
			_sub = Sub.NONE


func _tick_gather_return() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_depot()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		if _carrying > 0:
			GameState.add_salvage(_carrying)
		_carrying = 0
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_follow_navigation()


func _find_nearest_depot():
	var nearest = null
	var nearest_dist := INF
	for d in get_tree().get_nodes_in_group("depot"):
		if not is_instance_valid(d):
			continue
		var dist: float = global_position.distance_to(d.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = d
	return nearest
