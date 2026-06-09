class_name AITactician
extends RefCounted

# Tactical layer. Receives a posture order from the strategist (attack a position,
# hold, retreat to base) and translates it into per-unit movement commands using
# the same move_to() API the player uses. Re-evaluated every ~1 second by the
# controller. Auto-attack en route is handled by each unit's existing combat
# behavior — the tactician does NOT override that.
#
# H3 design notes:
#   - Pre-fix, evaluate() re-issued move_to() to every combat unit every tick,
#     snapping engaged units back into MOVE mid-fight (no kiting), forcing a
#     repath every second, and sending fresh spawns solo across the map. The
#     three failure modes were independent; all three are addressed here.
#   - Skip re-issue if the unit is already at the target (ARRIVED_THRESHOLD_PX)
#     or already engaged (Unit.is_engaged()) - let local combat play out.
#   - Cache the last issued target per unit so an unchanged order isn't re-emitted.
#   - In ATTACK, units stage at a rally point near the AI Barracks (or HQ if no
#     Barracks) until ATTACK_DISPATCH_GROUP_SIZE have arrived; then they all
#     dispatch to the attack target together. Fresh spawns join the rally; they
#     don't trickle out solo. RETREAT bypasses the rally (fall back NOW).

enum Order { HOLD, ATTACK, RETREAT }

# Default dispatch threshold when no CLI override is in play. Live value is
# read from GameState.dispatch_group_size at evaluate time so balance sweeps
# can vary it per-match via --dispatch-group-size=N without recompiling.
const ATTACK_DISPATCH_GROUP_SIZE := 4
const ARRIVED_THRESHOLD_PX := 100.0
const TARGET_REISSUE_EPSILON_PX := 8.0
const RALLY_OFFSET := Vector2(0, 80)

var controller: AIController = null
var _order: int = Order.HOLD
var _target_pos: Vector2 = Vector2.ZERO

# Per-unit tracking. Keys are unit instance ids; values are the last position
# we issued via move_to / the dispatched flag. Pruned each evaluate() for dead
# units so the dictionaries don't bloat across a long match.
var _last_target_by_unit: Dictionary = {}  # int -> Vector2
var _dispatched: Dictionary = {}           # int -> true


func set_attack_order(pos: Vector2) -> void:
	_order = Order.ATTACK
	_target_pos = pos
	# Order change invalidates prior dispatch / target caches so the rally
	# stages anew toward the new objective.
	_dispatched.clear()
	_last_target_by_unit.clear()


func set_retreat_order(home: Vector2) -> void:
	_order = Order.RETREAT
	_target_pos = home
	_dispatched.clear()
	_last_target_by_unit.clear()


func set_hold_order() -> void:
	_order = Order.HOLD


func evaluate() -> void:
	if controller == null:
		return
	if _order == Order.HOLD:
		return
	var units: Array = controller.get_combat_units()
	_prune_dead(units)
	if _order == Order.RETREAT:
		_evaluate_retreat(units)
	else:
		_evaluate_attack(units)


func _evaluate_attack(units: Array) -> void:
	var rally_pt: Vector2 = _rally_point()
	# Pass 1: route undispatched units to the rally, dispatched ones to the
	# attack target. Engaged units pass through untouched - their local combat
	# tick owns positioning until disengagement.
	var staged_count: int = 0
	for u in units:
		if not is_instance_valid(u) or not u.has_method("move_to"):
			continue
		if u.is_engaged():
			continue
		var id: int = u.get_instance_id()
		if _dispatched.has(id):
			if u.global_position.distance_to(_target_pos) <= ARRIVED_THRESHOLD_PX:
				continue
			_issue_if_changed(u, _target_pos)
		else:
			if u.global_position.distance_to(rally_pt) <= ARRIVED_THRESHOLD_PX:
				staged_count += 1
				continue
			_issue_if_changed(u, rally_pt)
	# Pass 2: if the rally has reached critical mass, dispatch every staged
	# unit at once. They march together rather than trickling.
	if staged_count >= GameState.dispatch_group_size:
		var dispatched_count: int = 0
		for u in units:
			if not is_instance_valid(u) or not u.has_method("move_to"):
				continue
			var id: int = u.get_instance_id()
			if _dispatched.has(id):
				continue
			if u.global_position.distance_to(rally_pt) > ARRIVED_THRESHOLD_PX:
				continue
			_dispatched[id] = true
			dispatched_count += 1
			_issue_if_changed(u, _target_pos)
		if dispatched_count > 0:
			MatchStats.log_event(&"ai_unit_dispatched", {
				"controller": controller.get_controller_id(),
				"count": dispatched_count,
			})


func _evaluate_retreat(units: Array) -> void:
	# RETREAT is a "fall back NOW" order - no rally, no engagement skip; the
	# unit's home is more important than the current fight.
	for u in units:
		if not is_instance_valid(u) or not u.has_method("move_to"):
			continue
		_issue_if_changed(u, _target_pos)


func _issue_if_changed(u, pos: Vector2) -> void:
	var id: int = u.get_instance_id()
	if _last_target_by_unit.has(id):
		var prev: Vector2 = _last_target_by_unit[id]
		if prev.distance_to(pos) < TARGET_REISSUE_EPSILON_PX:
			return
	var src: String = CommandBus.SRC_AI_PLAYER_SLOT if controller.as_player_slot else CommandBus.SRC_AI_OPPOSING
	CommandBus.issue("move", u, {"target": pos}, src)
	_last_target_by_unit[id] = pos


func _rally_point() -> Vector2:
	# Stage near the Barracks if it exists (units spawn there, shorter walk);
	# otherwise stage near the HQ. Offset south so the rally doesn't overlap
	# the spawn position itself.
	if controller.has_barracks():
		return controller.get_barracks_position() + RALLY_OFFSET
	return controller.get_hq_position() + RALLY_OFFSET


func _prune_dead(live_units: Array) -> void:
	if _last_target_by_unit.is_empty() and _dispatched.is_empty():
		return
	var alive_ids: Dictionary = {}
	for u in live_units:
		if is_instance_valid(u):
			alive_ids[u.get_instance_id()] = true
	for id in _last_target_by_unit.keys():
		if not alive_ids.has(id):
			_last_target_by_unit.erase(id)
			_dispatched.erase(id)


func get_order_name() -> String:
	match _order:
		Order.ATTACK: return "ATTACK"
		Order.RETREAT: return "RETREAT"
		_: return "HOLD"
