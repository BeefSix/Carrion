extends Node

# Per-tick state checksum (NETCODE harness Phase 4).
#
# Hashes the gameplay-relevant sim state into a single int every N physics
# ticks and logs it via ReplayRecorder. When a replay diverges from a
# recording, the comparison of these hash streams identifies the first
# diverging tick.
#
# What's hashed:
#   - Units (player_units + ai_units): position (int px), HP, faction, side
#   - Buildings (player_buildings + ai_buildings): position, HP
#   - Zombies group: count + aggregate position hash
#   - GameState.salvage, SimRng.tick
#
# Stable ordering: per group, entries are sorted by (pos.x, pos.y, hp) before
# hashing. Phase 7 will add a true spawn_ordinal field for a stricter stable
# id; for now position+hp is enough to detect drift since any divergence
# perturbs at least one of those.
#
# Cadence: every CHECKSUM_INTERVAL_TICKS ticks. 60 = 1 sim second. Low enough
# to catch drift fast, high enough to keep the replay log size sane (1
# checksum per second × 10 min match = 600 hashes).

const CHECKSUM_INTERVAL_TICKS := 60

var _last_logged_tick: int = -1


func _physics_process(_delta: float) -> void:
	# Run after the rest of the sim has stepped this tick. GameState advances
	# sim_ticks in its own _physics_process; autoload ordering means GameState
	# may not have ticked yet on this exact frame, so we read sim_ticks AFTER
	# checking is_recording (a tick where ticks==0 still gets logged once).
	if not ReplayRecorder.is_recording and not ReplayRecorder.is_playing:
		return
	var t: int = GameState.sim_ticks
	if t == _last_logged_tick:
		return
	if t % CHECKSUM_INTERVAL_TICKS != 0:
		return
	_last_logged_tick = t
	var h := compute_checksum()
	if ReplayRecorder.is_recording:
		ReplayRecorder.record_checksum(h)
	if ReplayRecorder.is_playing:
		ReplayRecorder.compare_live_hash(t, h)


func compute_checksum() -> int:
	# Build a flat list of (sortable tuple) → hash. Sorting before hashing
	# kills order-of-iteration sensitivity (CLAUDE.md Rule #4 leaks would
	# show up here otherwise).
	var rows: Array = []
	_collect_units(rows, "player_units", 1)
	_collect_units(rows, "ai_units", 2)
	_collect_buildings(rows, "player_buildings", 1)
	_collect_buildings(rows, "ai_buildings", 2)
	_collect_zombies(rows)
	rows.sort()
	rows.append(["state", GameState.salvage, SimRng.tick])
	return hash(rows)


func _collect_units(rows: Array, group: String, side: int) -> void:
	for u in get_tree().get_nodes_in_group(group):
		if u == null or not is_instance_valid(u):
			continue
		var hp: int = u.hp if "hp" in u else 0
		var faction: int = u.faction if "faction" in u else -1
		var p: Vector2 = u.position
		rows.append([
			"u", side, int(p.x), int(p.y), hp, faction,
		])


func _collect_buildings(rows: Array, group: String, side: int) -> void:
	for b in get_tree().get_nodes_in_group(group):
		if b == null or not is_instance_valid(b):
			continue
		var hp: int = b.hp if "hp" in b else 0
		var p: Vector2 = b.position
		rows.append([
			"b", side, int(p.x), int(p.y), hp,
		])


func _collect_zombies(rows: Array) -> void:
	var positions: Array = []
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z):
			continue
		var p: Vector2 = z.position
		positions.append([int(p.x), int(p.y)])
	positions.sort()
	rows.append(["z", positions.size(), hash(positions)])
