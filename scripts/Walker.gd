extends "res://scripts/Unit.gd"

enum Sub { NONE, GATHER_APPROACH, GATHER_CHANNEL, GATHER_RETURN }

const SALVAGE_PER_TRIP := 25
const CHANNEL_TIME := 3.0
const INTERACTION_RANGE := 80.0
const SEARCH_RADIUS := 1000.0
# H13: when no lootable is in range, hold off the next scan for this long
# instead of re-iterating the lootable group every physics frame.
const LOOTABLE_RETRY_INTERVAL := 1.0

var _sub: Sub = Sub.NONE
var _target_lootable = null
var _home_base = null
var _channel_timer := 0.0
var _carrying := 0
var _lootable_retry_timer: float = 0.0


func _ready() -> void:
	super._ready()
	# Load-bearing: Shambler.gd's perception filter exempts the "walkers"
	# group from targeting — this is what makes Walker "stroll through a
	# horde untouched" (DESIGN_MASTER §7.2). Without this line, Walkers
	# get eaten on contact and the Tribal economy collapses.
	add_to_group("walkers")


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


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		if _carrying > 0:
			_start_return_home()
		else:
			# H13: cool down between failed lootable scans instead of
			# re-iterating the lootable group every physics frame.
			_lootable_retry_timer = max(0.0, _lootable_retry_timer - delta)
			if _lootable_retry_timer <= 0.0:
				_try_find_lootable()
				if _sub == Sub.NONE:
					_lootable_retry_timer = LOOTABLE_RETRY_INTERVAL

	match _sub:
		Sub.GATHER_APPROACH:
			_tick_gather_approach()
		Sub.GATHER_CHANNEL:
			_tick_gather_channel(delta)
		Sub.GATHER_RETURN:
			_tick_gather_return()
		_:
			velocity = Vector2.ZERO


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
	var camp = _find_nearest_camp()
	if camp == null:
		velocity = Vector2.ZERO
		return
	_home_base = camp
	_sub = Sub.GATHER_RETURN
	_nav.target_position = camp.position


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
			_carrying += _target_lootable.take_salvage(SALVAGE_PER_TRIP)
		_home_base = _find_nearest_camp()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_sub = Sub.GATHER_RETURN
		_nav.target_position = _home_base.position


func _tick_gather_return() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_camp()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		if _carrying > 0:
			# Owner-aware routing via Unit.deposit_salvage so AI-spawned
			# Walkers credit their controller, not GameState.
			deposit_salvage(_carrying)
		_carrying = 0
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_follow_navigation()


func _find_nearest_camp():
	# Same-ownership preference as Looter._find_nearest_command_post - players
	# return to player's TC, AI Walkers (future Phase 2) return to AI's TC.
	var owner_group: String = "ai_buildings" if is_in_group("ai_units") else "player_buildings"
	var nearest = null
	var nearest_dist := INF
	for c in get_tree().get_nodes_in_group("tribal_camp"):
		if not is_instance_valid(c):
			continue
		if not c.is_in_group(owner_group):
			continue
		var d: float = global_position.distance_to(c.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = c
	if nearest != null:
		return nearest
	# Fallback: any TC.
	for c in get_tree().get_nodes_in_group("tribal_camp"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = c
	return nearest
