extends Node

# Autoload singleton owning all squads in the match. All squad mutations route
# through this manager so signals fire centrally and the HUD stays in sync.

signal squad_created(squad: Squad)
signal squad_disbanded(squad: Squad)
signal squad_updated(squad: Squad)
signal squad_membership_changed(squad: Squad)
signal squad_leader_changed(squad: Squad)

# Aura range: 6 tiles. Subordinate must be within this distance of an ancestor
# for that ancestor to contribute to the subordinate's aura bonus.
const AURA_RANGE_PX := 6.0 * 32.0
const AURA_RANGE_PX_SQ := AURA_RANGE_PX * AURA_RANGE_PX
const AURA_TICK_INTERVAL := 0.2  # 5Hz - dynamic proximity check only.
# Bonus per rank-level above the subordinate, per ancestor. 0.05 = +5%.
# Seasoned at d=1: +5%. Veteran at d=1/2: +10%/+5%. Captain at d=1/2/3:
# +15%/+10%/+5%. Single tuning knob for the entire leadership system.
const AURA_PERCENT_PER_LEVEL := 0.05
const SCATTER_DURATION := 90.0

# Posture -> per-unit Stance mapping. Squad posture writes through to all
# members' stance when set.
const POSTURE_TO_STANCE := {
	Squad.Posture.AGGRESSIVE: Unit.Stance.AGGRESSIVE,
	Squad.Posture.STANDARD: Unit.Stance.NEUTRAL,
	Squad.Posture.DEFENSIVE: Unit.Stance.PASSIVE,
}

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

var _aura_timer: float = 0.0


func _process(delta: float) -> void:
	# Scatter timers run at full delta (real-time). Aura proximity checks
	# run at 5Hz to keep cost down at population cap.
	_tick_scatter_timers(delta)
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = AURA_TICK_INTERVAL
		_tick_auras()


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
	_rebuild_command_tree(squad)
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
			u.squad_damage_bonus = 0.0
			u.squad_accuracy_bonus = 0.0
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
	_rebuild_command_tree(squad)
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
# triggers succession, sub-tree absorption, or 90s scatter as needed.
func on_member_died(unit) -> void:
	if unit == null or unit.squad == null:
		return
	var squad: Squad = unit.squad
	if not _squads.has(squad.id):
		return
	# Subordinates of the dying unit need a new commander. We delegate that to
	# _rebuild_command_tree below - it reassigns the survivor pool from
	# scratch using the rank ladder, which handles orphan absorption
	# deterministically without per-orphan logic here.
	squad.members.erase(unit)
	unit.squad = null
	unit.commander = null
	unit.squad_damage_bonus = 0.0
	unit.squad_accuracy_bonus = 0.0
	# Squad collapsed below minimum -> dissolve.
	if squad.members.size() < 2:
		disband_squad(squad)
		return
	# Squad-leader case: enter scatter state if no rank-2+ remains. If a
	# rank-2+ does remain, promote immediately and rebuild tree.
	if unit == squad.leader:
		_assign_leader_internal(squad)
		if squad.leader == null:
			# Leaderless - scatter timer counts down. squad_leader_changed
			# fires so the sidebar can show the timer.
			squad.scatter_timer = SCATTER_DURATION
			squad.command_tree.clear()
			for m in squad.members:
				if is_instance_valid(m):
					m.commander = null
			squad_leader_changed.emit(squad)
			squad_membership_changed.emit(squad)
			return
		squad.sort_members()
		_rebuild_command_tree(squad)
		squad_leader_changed.emit(squad)
		squad_membership_changed.emit(squad)
		return
	# Sub-leader case: a non-leader combat unit died. Rebuild the tree so
	# their orphans get reassigned. _rebuild_command_tree picks new commanders
	# from the remaining rank pool deterministically.
	_rebuild_command_tree(squad)
	squad_membership_changed.emit(squad)


func get_all_squads() -> Array:
	return _squads.values()


func get_squad_by_id(id: int) -> Squad:
	return _squads.get(id, null)


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
	_rebuild_command_tree(source)
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
	# If target was scattering and merge brought in a rank-2+ leader candidate,
	# end the scatter state immediately. Without this clear, the squad ends up
	# with a valid leader AND a ticking scatter timer - aura zeroed, detail
	# panel shows "(scattered)" despite having a real chain of command.
	if target.scatter_timer > 0.0 and target.leader != null:
		target.scatter_timer = 0.0
	_rebuild_command_tree(target)
	squad_membership_changed.emit(target)
	squad_leader_changed.emit(target)
	return ""


func _highest_rank(units: Array) -> int:
	var best: int = 0
	for u in units:
		if is_instance_valid(u) and u.veterancy_level > best:
			best = u.veterancy_level
	return best


# ----- Command tree -----

# Build commander -> direct-subordinates map. Strict rank hierarchy: each
# commander commands up to 2 of the next-rank-down combat units. Specialists
# (non-combat) attach under the squad leader without entering the tree.
# Called whenever membership / leader changes.
func _rebuild_command_tree(squad: Squad) -> void:
	squad.command_tree.clear()
	if squad.leader == null:
		for m in squad.members:
			if is_instance_valid(m):
				m.commander = null
		return
	# Clear all commander fields first.
	for m in squad.members:
		if is_instance_valid(m):
			m.commander = null
	# Partition members.
	var combat: Array = []
	var specialists: Array = []
	for m in squad.members:
		if not is_instance_valid(m):
			continue
		if m == squad.leader:
			continue
		if m.is_in_group("combat_units"):
			combat.append(m)
		else:
			specialists.append(m)
	# Specialists attach under the squad leader as Rookie-equivalent followers.
	# They get the leader's aura but aren't in the chain of command for succession.
	squad.command_tree[squad.leader] = []
	for sp in specialists:
		sp.commander = squad.leader
		squad.command_tree[squad.leader].append(sp)
	# Sort combat members by rank descending (Veteran -> Seasoned -> Rookie).
	combat.sort_custom(func(a, b): return a.veterancy_level > b.veterancy_level)
	# Available commanders, in BFS-frontier order. Each can take up to 2 direct
	# subordinates of the next rank down. Squad leader bootstrap.
	var frontier: Array = [squad.leader]
	for unit in combat:
		var assigned: bool = false
		for cmdr in frontier:
			var subs: Array = squad.command_tree.get(cmdr, [])
			# A commander only takes subordinates strictly below their rank.
			if cmdr == squad.leader or cmdr.veterancy_level > unit.veterancy_level:
				if subs.size() < 2:
					unit.commander = cmdr
					subs.append(unit)
					squad.command_tree[cmdr] = subs
					assigned = true
					break
		if not assigned:
			# Frontier is full at appropriate ranks. Fall back to attaching
			# directly to the squad leader (over-capacity is fine on the
			# leader; this is the "deformed squad" branch).
			unit.commander = squad.leader
			squad.command_tree[squad.leader].append(unit)
		# Only rank-2+ units can lead their own subordinates.
		if unit.veterancy_level >= Squad.SEASONED:
			squad.command_tree[unit] = []
			frontier.append(unit)


# ----- Aura -----

# Per-tick walk: for each in-squad combat unit, sum aura bonuses from each
# command-chain ancestor that's within AURA_RANGE_PX. Scattered squads grant
# no auras (members lose the bonus during the leaderless state).
func _tick_auras() -> void:
	for squad in _squads.values():
		if squad.is_scattering():
			for m in squad.members:
				if is_instance_valid(m):
					m.squad_damage_bonus = 0.0
					m.squad_accuracy_bonus = 0.0
			continue
		for m in squad.members:
			if not is_instance_valid(m) or m == squad.leader:
				continue
			var bonus: float = _compute_aura_for(m)
			m.squad_damage_bonus = bonus
			m.squad_accuracy_bonus = bonus
		# Squad leader gets no aura (top of the chain).
		if is_instance_valid(squad.leader):
			squad.leader.squad_damage_bonus = 0.0
			squad.leader.squad_accuracy_bonus = 0.0


func _compute_aura_for(unit) -> float:
	# Walk up the commander chain. Each ancestor in range contributes
	# max(0, (ancestor_rank - depth)) * 0.05 to the bonus.
	#   Seasoned at depth 1: (2-1)*0.05 = 0.05
	#   Veteran at depth 1:  (3-1)*0.05 = 0.10
	#   Veteran at depth 2:  (3-2)*0.05 = 0.05
	#   Captain at depth 1/2/3: 0.15 / 0.10 / 0.05
	# Each link must be within AURA_RANGE - i.e., subordinate's distance to
	# THAT specific ancestor must be <= range. Chain breakage at one level
	# does not break ancestor-of-ancestor visibility.
	var bonus: float = 0.0
	var depth: int = 1
	var cur = unit.commander
	while cur != null and is_instance_valid(cur):
		# Squared-distance compare saves a sqrt per ancestor per tick.
		if unit.global_position.distance_squared_to(cur.global_position) <= AURA_RANGE_PX_SQ:
			var per_level: float = max(0.0, float(cur.veterancy_level - depth)) * AURA_PERCENT_PER_LEVEL
			bonus += per_level
		cur = cur.commander
		depth += 1
		if depth > 6:  # safety: deepest possible tree (Captain) has depth 4
			break
	return bonus


# ----- Scatter -----

func _tick_scatter_timers(delta: float) -> void:
	# Iterate over a copy because resolutions may disband. The HUD polls
	# scatter_timer in its own _process for the live countdown - we do NOT
	# emit squad_updated every tick (that would rebuild detail rows 60x/sec).
	for squad in _squads.values().duplicate():
		if not squad.is_scattering():
			continue
		squad.scatter_timer -= delta
		if squad.scatter_timer <= 0.0:
			squad.scatter_timer = 0.0
			_resolve_scatter(squad)


func _resolve_scatter(squad: Squad) -> void:
	# End of scatter. If any rank-2+ unit is in the squad, promote them and
	# rebuild. Otherwise dissolve.
	_assign_leader_internal(squad)
	if squad.leader == null:
		disband_squad(squad)
		return
	squad.sort_members()
	_rebuild_command_tree(squad)
	squad_leader_changed.emit(squad)
	squad_updated.emit(squad)


# Called from Unit._on_level_up. If the unit's squad is scattering and the
# new rank is Seasoned+, the unit takes over immediately.
func on_unit_promoted(unit) -> void:
	if unit == null or unit.squad == null:
		return
	var squad: Squad = unit.squad
	if not squad.is_scattering():
		return
	if unit.veterancy_level < Squad.SEASONED:
		return
	squad.scatter_timer = 0.0
	_resolve_scatter(squad)


# ----- Posture -----

# Sets the squad's posture and writes through to each member's per-unit Stance
# per the POSTURE_TO_STANCE mapping. The HUD's posture dropdown calls this.
func set_posture(squad: Squad, posture: int) -> void:
	if squad == null:
		return
	squad.posture = posture
	var target_stance: int = POSTURE_TO_STANCE.get(posture, Unit.Stance.NEUTRAL)
	for m in squad.members:
		if is_instance_valid(m):
			m.set_stance(target_stance)
	squad_updated.emit(squad)


func set_formation(squad: Squad, formation: int) -> void:
	# Phase 4: data-only. Movement logic is deferred to a follow-on phase.
	if squad == null:
		return
	squad.formation = formation
	squad_updated.emit(squad)
