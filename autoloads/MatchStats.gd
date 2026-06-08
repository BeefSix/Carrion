extends Node

# Per-match event log. JSONL: one JSON object per line. Header (schema +
# constants) is the first line; events follow. Single persistent FileAccess
# handle from match_start through match_end - no per-flush reopens, no
# append-mode dance.
#
# Read in Python:
#   import json
#   rows = [json.loads(l) for l in open(path) if l.strip()]
#   header, events = rows[0], rows[1:]
#
# Flush policy:
#   - Wall-time interval (FLUSH_INTERVAL_WALL_SEC) - bounded data loss on crash.
#   - Buffer-size cap (BUFFER_CAP) - bounded memory.
#   - match_end - guaranteed flush of the final tail.
# Picked wall-time over sim-time so post-match overlays/UI don't sit on a
# stale buffer while sim_ticks is frozen.

const FLUSH_INTERVAL_WALL_SEC := 2.0
const BUFFER_CAP := 256

# Bump when the header layout or event field semantics change. Older logs
# remain readable but downstream analysis tools key off this.
const SCHEMA_VERSION := 1

const NoiseFieldScript := preload("res://scripts/NoiseField.gd")
const ShamblerScript := preload("res://scripts/Shambler.gd")

var _file: FileAccess = null
var _path: String = ""
var _buffer: PackedStringArray = PackedStringArray()
var _flush_timer: float = 0.0


func _process(delta: float) -> void:
	if _file == null:
		return
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH_INTERVAL_WALL_SEC
		_flush()


func match_start() -> void:
	# If a previous match wasn't ended cleanly (crash, dev quit-during-match),
	# close it out before starting fresh so the file handle isn't leaked.
	if _file != null:
		_buffer.append(JSON.stringify({
			"t": GameState.sim_seconds(),
			"e": "match_end",
			"result": "abandoned",
		}))
		_flush()
		_file.close()
		_file = null
	var dir := "user://matches"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	_path = "%s/match_%d_%s.jsonl" % [dir, GameState.match_seed, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[MatchStats] failed to open %s for write" % _path)
		return
	_file.store_line(JSON.stringify(_build_header()))
	_file.flush()
	_flush_timer = FLUSH_INTERVAL_WALL_SEC
	print("[MatchStats] logging to %s" % _path)


func log_event(event_type: StringName, data: Dictionary) -> void:
	# Named log_event to avoid colliding with Godot's built-in `log()`
	# (math base-e), which would otherwise shadow at call sites.
	if _file == null:
		return
	var row: Dictionary = {"t": GameState.sim_seconds(), "e": String(event_type)}
	row.merge(data)
	_buffer.append(JSON.stringify(row))
	if _buffer.size() >= BUFFER_CAP:
		_flush()


func match_end(data: Dictionary) -> void:
	if _file == null:
		return
	var row: Dictionary = {"t": GameState.sim_seconds(), "e": "match_end"}
	row.merge(data)
	_buffer.append(JSON.stringify(row))
	_flush()
	_file.close()
	_file = null
	print("[MatchStats] match log closed: %s" % _path)


func _flush() -> void:
	if _file == null or _buffer.is_empty():
		return
	for line in _buffer:
		_file.store_line(line)
	_buffer.clear()
	_file.flush()


func _build_header() -> Dictionary:
	var player_name: String = _faction_name(GameState.player_faction)
	# When ai_enabled is false the opposing HQ is inert (no AI faction).
	# Record "none" so post-hoc analysis can separate human-vs-AI from
	# human-vs-dummy matches.
	var ai_name: String = "none"
	if GameState.ai_enabled:
		# AI is hardcoded MILITARY in Main._spawn_ai_opponent today (see
		# AUDIT.md H4) - keep the header honest about that.
		ai_name = _faction_name(GameState.Faction.MILITARY)
	var map_source: String = "custom" if GameState.custom_map_path != "" else "procedural"
	return {
		"schema": SCHEMA_VERSION,
		"seed": GameState.match_seed,
		"matchup": {"player": player_name, "ai": ai_name},
		"ai_vs_ai": GameState.ai_vs_ai_mode,
		"map": {"source": map_source, "size_tiles": 192},
		"started_wall": Time.get_datetime_string_from_system(),
		"constants": {
			"starting_salvage": GameState.STARTING_SALVAGE,
			"horde_thresholds": [
				NoiseFieldScript.SMALL_THRESHOLD,
				NoiseFieldScript.MEDIUM_THRESHOLD,
				NoiseFieldScript.LARGE_THRESHOLD,
				NoiseFieldScript.CATASTROPHIC_THRESHOLD,
			],
			"horde_sizes": [
				NoiseFieldScript.SMALL_SIZE,
				NoiseFieldScript.MEDIUM_SIZE,
				NoiseFieldScript.LARGE_SIZE,
				NoiseFieldScript.CATASTROPHIC_SIZE,
			],
			"horde_cooldown_sec": NoiseFieldScript.HORDE_COOLDOWN,
			"max_zombie_pop": NoiseFieldScript.MAX_ZOMBIE_POPULATION,
			"noise_decay_rate": NoiseFieldScript.NOISE_DECAY_RATE,
			"hearing_range_px": ShamblerScript.HEARING_RANGE_PX,
			"vision_range_px": ShamblerScript.VISION_RANGE_PX,
			"shambler_attack_damage": ShamblerScript.ATTACK_DAMAGE,
		},
	}


func _faction_name(f: int) -> String:
	match f:
		GameState.Faction.MILITARY: return "MILITARY"
		GameState.Faction.TRIBAL: return "TRIBAL"
		GameState.Faction.ZOMBIE: return "ZOMBIE"
		GameState.Faction.NEUTRAL: return "NEUTRAL"
		GameState.Faction.SURVIVOR: return "SURVIVOR"
		_: return "UNKNOWN"
