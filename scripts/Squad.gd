class_name Squad
extends RefCounted

# Rank constants - mirror Unit.veterancy_level. Captain (4) reserved for the
# promotion ceremony work that's deferred per the squad design doc.
const ROOKIE := 1
const SEASONED := 2
const VETERAN := 3
const CAPTAIN := 4

# Squad max capacity by the LEADER's rank. Rookie can't lead.
const CAPACITY_BY_RANK := {
	ROOKIE: 0,
	SEASONED: 3,
	VETERAN: 5,
	CAPTAIN: 9,
}

# Formation/posture - data placeholders for Phase 4. Posture writes through
# to each member's stance when set.
enum Formation { STANDARD, LINE, WEDGE, COLUMN, SCATTERED }
enum Posture { STANDARD, AGGRESSIVE, DEFENSIVE }

var id: int = 0
var display_name: String = ""
var faction: int = 0  # GameState.Faction value
var members: Array = []  # Array of Unit
var leader = null  # Unit reference
var formation: int = Formation.STANDARD
var posture: int = Posture.STANDARD
# Phase 4: time remaining in leaderless scatter state. 0.0 means not scattering.
var scatter_timer: float = 0.0


func get_capacity() -> int:
	if leader == null or not is_instance_valid(leader):
		return 0
	return CAPACITY_BY_RANK.get(leader.veterancy_level, 0)


func is_full() -> bool:
	return members.size() >= get_capacity()


func is_valid() -> bool:
	# A squad needs >=2 members and a rank-2+ leader. Used by validation and
	# survives-membership-change checks.
	if members.size() < 2:
		return false
	if leader == null or not is_instance_valid(leader):
		return false
	return leader.veterancy_level >= SEASONED


func sort_members() -> void:
	# Display order: leader first, then by rank descending, then by instance_id
	# for stability. The doc forbids manual reordering.
	members.sort_custom(_compare_members)


func _compare_members(a, b) -> bool:
	if a == leader:
		return true
	if b == leader:
		return false
	if a.veterancy_level != b.veterancy_level:
		return a.veterancy_level > b.veterancy_level
	return a.get_instance_id() < b.get_instance_id()


static func rank_name(level: int) -> String:
	match level:
		ROOKIE: return "Rookie"
		SEASONED: return "Seasoned"
		VETERAN: return "Veteran"
		CAPTAIN: return "Captain"
		_: return "Unknown"
