extends Node

# Autoload singleton owning all squads in the match. All squad mutations route
# through this manager so signals fire centrally and the HUD stays in sync.

signal squad_created(squad: Squad)
signal squad_disbanded(squad: Squad)
signal squad_updated(squad: Squad)
signal squad_membership_changed(squad: Squad)
signal squad_leader_changed(squad: Squad)

const NATO_NAMES := [
	"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
	"Golf", "Hotel", "India", "Juliet", "Kilo", "Lima",
	"Mike", "November", "Oscar", "Papa", "Quebec", "Romeo",
	"Sierra", "Tango", "Uniform", "Victor", "Whiskey", "X-ray",
	"Yankee", "Zulu",
]

var _squads: Dictionary = {}  # id -> Squad
var _next_id: int = 1
var _name_counter: int = 0


func reset() -> void:
	_squads.clear()
	_next_id = 1
	_name_counter = 0


# Returns Squad on success, String error message on validation failure.
func create_squad(units: Array, faction: int) -> Variant:
	var err := validate_composition(units)
	if err != "":
		return err
	var squad := Squad.new()
	squad.id = _next_id
	_next_id += 1
	squad.display_name = _next_default_name()
	squad.faction = faction
	squad.members = units.duplicate()
	for u in units:
		if is_instance_valid(u):
			u.squad = squad
	_assign_leader_internal(squad)
	squad.sort_members()
	_squads[squad.id] = squad
	squad_created.emit(squad)
	return squad


func disband_squad(squad: Squad) -> void:
	if squad == null or not _squads.has(squad.id):
		return
	for u in squad.members:
		if is_instance_valid(u):
			u.squad = null
			u.commander = null
	var copy: Squad = squad
	_squads.erase(squad.id)
	squad_disbanded.emit(copy)


func validate_composition(units: Array) -> String:
	if units == null or units.size() < 2:
		return "Squad requires at least 2 units."
	# All same faction
	var first_faction = units[0].faction
	for u in units:
		if not is_instance_valid(u):
			return "Selection contains invalid units."
		if u.faction != first_faction:
			return "Squad members must be the same faction."
		if u.squad != null:
			return "One or more selected units are already in a squad."
	# Highest rank determines capacity
	var highest_rank: int = 0
	for u in units:
		if u.veterancy_level > highest_rank:
			highest_rank = u.veterancy_level
	if highest_rank < Squad.SEASONED:
		return "Squad requires at least one Seasoned or higher unit as leader."
	var capacity: int = Squad.CAPACITY_BY_RANK.get(highest_rank, 0)
	if units.size() > capacity:
		return "Selected units (%d) exceed leadership capacity. Highest rank (%s) can lead up to %d." % [
			units.size(), Squad.rank_name(highest_rank), capacity,
		]
	return ""


# Picks the highest-rank member as leader; tiebreak by XP, then by distance to centroid.
func _assign_leader_internal(squad: Squad) -> void:
	var candidates: Array = []
	for u in squad.members:
		if is_instance_valid(u) and u.veterancy_level >= Squad.SEASONED:
			candidates.append(u)
	if candidates.is_empty():
		squad.leader = null
		return
	var centroid: Vector2 = _centroid(squad.members)
	candidates.sort_custom(func(a, b):
		if a.veterancy_level != b.veterancy_level:
			return a.veterancy_level > b.veterancy_level
		var axp: float = a.get_xp_total()
		var bxp: float = b.get_xp_total()
		if not is_equal_approx(axp, bxp):
			return axp > bxp
		return a.global_position.distance_squared_to(centroid) < b.global_position.distance_squared_to(centroid)
	)
	squad.leader = candidates[0]


func reassign_leader(squad: Squad) -> void:
	var old_leader = squad.leader
	_assign_leader_internal(squad)
	squad.sort_members()
	if old_leader != squad.leader:
		squad_leader_changed.emit(squad)
	squad_updated.emit(squad)


func _centroid(units: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for u in units:
		if is_instance_valid(u):
			sum += u.global_position
			n += 1
	return sum / max(n, 1)


func _next_default_name() -> String:
	var idx: int = _name_counter % NATO_NAMES.size()
	var cycle: int = _name_counter / NATO_NAMES.size()
	_name_counter += 1
	if cycle == 0:
		return NATO_NAMES[idx]
	return "%s-%d" % [NATO_NAMES[idx], cycle + 1]


# Called from Unit._die when a squad member dies. Updates membership and
# triggers succession or disband as needed.
func on_member_died(unit) -> void:
	if unit == null or unit.squad == null:
		return
	var squad: Squad = unit.squad
	if not _squads.has(squad.id):
		return
	squad.members.erase(unit)
	unit.squad = null
	unit.commander = null
	# Squad collapsed below minimum membership -> dissolve.
	if squad.members.size() < 2:
		disband_squad(squad)
		return
	# Leader died -> reassign. If no rank-2+ remains, dissolve (Phase 4 will
	# replace this branch with the 90s scatter timer).
	if unit == squad.leader:
		_assign_leader_internal(squad)
		if squad.leader == null:
			disband_squad(squad)
			return
		squad.sort_members()
		squad_leader_changed.emit(squad)
	squad_membership_changed.emit(squad)


func get_all_squads() -> Array:
	return _squads.values()


func get_squad_by_id(id: int) -> Squad:
	return _squads.get(id, null)


# Lookup helper used by the sidebar when the player clicks on a unit and we
# need to know which squad to highlight.
func squad_of(unit) -> Squad:
	if unit == null or not is_instance_valid(unit):
		return null
	return unit.squad


func rename_squad(squad: Squad, new_name: String) -> void:
	if squad == null or new_name.strip_edges() == "":
		return
	squad.display_name = new_name.substr(0, 24)
	squad_updated.emit(squad)


# Split: removes `members_to_move` from `source` and forms a new squad with them.
# Both resulting squads must be valid (>=2 members, rank-2+ leader). Returns
# the new Squad on success, String error on failure.
func split_squad(source: Squad, members_to_move: Array) -> Variant:
	if source == null:
		return "No source squad."
	if members_to_move.size() < 2:
		return "Split requires at least 2 units."
	# All units must belong to source.
	for u in members_to_move:
		if not is_instance_valid(u) or u.squad != source:
			return "Selected units don't all belong to this squad."
	# Compute remaining set.
	var remaining: Array = []
	for u in source.members:
		if not (u in members_to_move):
			remaining.append(u)
	if remaining.size() < 2:
		return "Remaining squad would have fewer than 2 units."
	# Both halves need a rank-2+ leader candidate.
	if _highest_rank(members_to_move) < Squad.SEASONED:
		return "Split squad requires at least one Seasoned or higher unit."
	if _highest_rank(remaining) < Squad.SEASONED:
		return "Remaining squad would have no leader."
	# Capacity check for both halves.
	if members_to_move.size() > Squad.CAPACITY_BY_RANK.get(_highest_rank(members_to_move), 0):
		return "Split selection exceeds new leader's capacity."
	if remaining.size() > Squad.CAPACITY_BY_RANK.get(_highest_rank(remaining), 0):
		return "Remaining squad would exceed leader capacity."
	# Detach moved members from source first - this clears u.squad so the
	# create_squad validation pre-check (u.squad != null) doesn't reject them.
	for u in members_to_move:
		source.members.erase(u)
		u.squad = null
		u.commander = null
	# Form the new squad.
	var result = create_squad(members_to_move, source.faction)
	if result is String:
		# Should not happen given the upfront validation; restore source as a
		# best-effort rollback before returning the error.
		for u in members_to_move:
			u.squad = source
			source.members.append(u)
		source.sort_members()
		return result
	# Reassign leader on the source (its old leader may have moved).
	_assign_leader_internal(source)
	source.sort_members()
	squad_membership_changed.emit(source)
	squad_leader_changed.emit(source)
	return result


# Merge: moves all of source's members into target, disbands source. Combined
# membership must fit target's leader-capacity. Returns "" on success, error msg
# on failure.
func merge_squads(target: Squad, source: Squad) -> String:
	if target == null or source == null:
		return "Invalid squads."
	if target == source:
		return "Cannot merge a squad with itself."
	if target.faction != source.faction:
		return "Squads must be the same faction."
	# Capacity check: combined membership and the strongest possible leader from
	# the union must satisfy capacity. (Target may gain a higher-rank leader from
	# source after merge.)
	var combined_size: int = target.members.size() + source.members.size()
	var combined_rank: int = max(_highest_rank(target.members), _highest_rank(source.members))
	if combined_size > Squad.CAPACITY_BY_RANK.get(combined_rank, 0):
		return "Combined squad would exceed leader capacity."
	# Move members from source into target.
	for u in source.members:
		if not is_instance_valid(u):
			continue
		u.squad = target
		target.members.append(u)
	# Disband source (members already reassigned, so source.members.clear()
	# would orphan them - just remove source from the registry without iterating
	# its members).
	source.members.clear()
	_squads.erase(source.id)
	squad_disbanded.emit(source)
	# Reassign target leader from the new combined pool.
	_assign_leader_internal(target)
	target.sort_members()
	squad_membership_changed.emit(target)
	squad_leader_changed.emit(target)
	return ""


func _highest_rank(units: Array) -> int:
	var best: int = 0
	for u in units:
		if is_instance_valid(u) and u.veterancy_level > best:
			best = u.veterancy_level
	return best
