extends Node

# Replay recording (Phase 3 of NETCODE harness).
#
# Writes a JSONL stream parallel to MatchStats so the schemas can evolve
# independently. File layout:
#
#   line 0: {schema: 1, seed: N, started_wall: "...", map: {...}, town: {...}}
#   line 1+: one of
#     - {tick: N, kind: "cmd", src: "player"|"ai_player_slot"|"ai_opposing",
#        actor: <id>, cmd: "move"|"attack"|..., args: {...}}
#     - {tick: N, kind: "hash", h: <int>}
#     - {kind: "end", t: <sim_sec>, result: "...", ...}
#
# Argument values get JSON-coerced: Vector2 → [x, y], Node ref → {"_node": id}.
# Decoding (Phase 5) reverses this and rebinds nodes by id at apply time.
#
# Gated on:
#   - CLI flag --record-replay (always record this match)
#   - or ai_vs_ai_mode (always record headless AI matches for the CI loop)

const SCHEMA_VERSION := 1

var is_recording: bool = false
var is_playing: bool = false

var _file: FileAccess = null
var _path: String = ""


func should_record() -> bool:
	# Auto-record AI-vs-AI matches (the determinism CI lives there) and
	# honor the explicit CLI flag for any other recording.
	if GameState.ai_vs_ai_mode:
		return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--record-replay":
			return true
	return false


func start_recording(town_data: Dictionary) -> void:
	# Called from Main._ready after GameState.reset_match and town generation
	# so seed + town are both finalized. No-op when not recording.
	if not should_record():
		return
	var dir := "user://replays"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	_path = "%s/replay_%d_%s.jsonl" % [dir, GameState.match_seed, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[ReplayRecorder] failed to open %s for write" % _path)
		return
	var header := {
		"schema": SCHEMA_VERSION,
		"seed": GameState.match_seed,
		"started_wall": Time.get_datetime_string_from_system(),
		"ai_vs_ai": GameState.ai_vs_ai_mode,
		"player_faction": GameState.faction_name(GameState.player_faction),
		"map": {
			"source": "custom" if GameState.custom_map_path != "" else "procedural",
			"custom_path": GameState.custom_map_path,
		},
		# Town data snapshot — sidesteps "is town generation seeded?" by
		# replaying the same lootables list at the same positions. Larger
		# header but pennies of disk and one-shot at match start.
		"town": _serialize_town(town_data),
	}
	_file.store_line(JSON.stringify(header))
	_file.flush()
	is_recording = true
	print("[ReplayRecorder] recording → %s" % _path)


func record_command(kind: String, actor, args: Dictionary, src: String) -> void:
	# Called by CommandBus on every live issuance. No-op if not recording.
	if not is_recording or _file == null:
		return
	var row := {
		"tick": GameState.sim_ticks,
		"kind": "cmd",
		"src": src,
		"actor": actor.get_instance_id() if (actor != null and is_instance_valid(actor)) else 0,
		"cmd": kind,
		"args": _encode_args(args),
	}
	_file.store_line(JSON.stringify(row))


func record_checksum(h: int) -> void:
	if not is_recording or _file == null:
		return
	_file.store_line(JSON.stringify({
		"tick": GameState.sim_ticks,
		"kind": "hash",
		"h": h,
	}))


func stop_recording(end_payload: Dictionary) -> void:
	if not is_recording or _file == null:
		return
	var row := {"kind": "end", "t": GameState.sim_seconds()}
	row.merge(end_payload)
	_file.store_line(JSON.stringify(row))
	_file.flush()
	_file.close()
	_file = null
	is_recording = false
	print("[ReplayRecorder] closed → %s" % _path)


func _serialize_town(town_data: Dictionary) -> Dictionary:
	# tile_grid as PackedByteArray serializes to a JSON array of ints, which
	# is fine — 36864 ints (192*192). Could base64 later if size matters.
	var lootables: Array = []
	for entry in town_data.get("lootables", []):
		var pos: Vector2 = entry.get("pos", Vector2.ZERO)
		lootables.append({"pos": [pos.x, pos.y], "type": entry.get("type", "residential")})
	var grid_arr: Array = []
	var grid = town_data.get("tile_grid", null)
	if grid != null:
		grid_arr.resize(grid.size())
		for i in range(grid.size()):
			grid_arr[i] = grid[i]
	return {"lootables": lootables, "tile_grid": grid_arr}


func _encode_args(args: Dictionary) -> Dictionary:
	# JSON-coerce values. Vector2 → [x, y], node refs → {"_node": id}.
	# Anything already a primitive passes through.
	var out := {}
	for key in args.keys():
		var v = args[key]
		if v is Vector2:
			out[key] = [v.x, v.y]
		elif v is Object and is_instance_valid(v):
			out[key] = {"_node": v.get_instance_id()}
		else:
			out[key] = v
	return out
