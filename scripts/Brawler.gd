extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 36.0
const ATTACK_DAMAGE := 22
const ATTACK_PERIOD := 1.0
const NOISE_PER_HIT := 0.0
const ENGAGE_RANGE := 200.0
const RETARGET_INTERVAL := 0.3

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _physics_process(delta: float) -> void:
	if tick_flinch(delta):
		return
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		elif stance == Stance.AGGRESSIVE:
			_try_strike_in_range(delta)
		return

	if stance == Stance.PASSIVE:
		velocity = Vector2.ZERO
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile()

	if _target == null or not is_instance_valid(_target):
		velocity = Vector2.ZERO
		return

	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if _attack_cooldown <= 0:
			_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
			_attack_cooldown = ATTACK_PERIOD
	else:
		_nav.target_position = _target.global_position
		_follow_navigation()


func _try_strike_in_range(delta: float) -> void:
	# Attack-while-moving (melee): hit only if a hostile is already within
	# ATTACK_RANGE. Do NOT deviate from the nav path to chase - the player's
	# move order has priority. _delta is unused but kept for symmetry with the
	# ranged-unit helpers.
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile()
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
		_attack_cooldown = ATTACK_PERIOD


# Survivor Brawler engages anything that isn't a Survivor or neutral - zombies,
# military, tribal all trigger combat. Melee silent (NOISE_PER_HIT = 0).
func _find_nearest_hostile():
	var best = null
	var best_dist := ENGAGE_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == GameState.Faction.SURVIVOR or u.faction == GameState.Faction.NEUTRAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(ENGAGE_RANGE)


func _find_nearest_hostile_hq(range_px: float):
	# Survivor Brawler engages anything non-Survivor, including opposing HQs.
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
