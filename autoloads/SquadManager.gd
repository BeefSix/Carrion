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
