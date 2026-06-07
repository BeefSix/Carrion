extends Node

signal salvage_changed(new_value: int)

# Canonical project-wide Faction enum (consolidated 2026-06 per audit response
# #7). Was previously split: GameState.Faction had 3 values, Unit.Faction had 5
# with SURVIVOR at a different ordinal - latent bug if anything cross-compared
# the two. Order preserves the previous Unit.Faction ordering so existing
# scene files' faction = N values stay semantically correct without editing.
enum Faction { MILITARY, TRIBAL, ZOMBIE, NEUTRAL, SURVIVOR }

const STARTING_SALVAGE := 200

var salvage: int = STARTING_SALVAGE:
	set(value):
		salvage = value
		salvage_changed.emit(value)

var player_faction: Faction = Faction.MILITARY
var ai_enabled: bool = false
# When set, Main.gd loads map data from this JSON path instead of running the
# procedural TownPlanner. Empty string = procedural. Used by the image-to-map
# PoC pipeline to feed extracted-from-image map data into the gameplay layer.
var custom_map_path: String = ""

# Match-scoped seed picked in reset_match(). Stored so MatchStats can log it
# in the JSONL header and so future deterministic replays can reuse it.
# Overridable via --seed=N CLI arg (after Godot's `--` separator).
var match_seed: int = 0

# Sim-time clock. Increments once per physics frame while _in_match is true,
# so 60 ticks = 1 sim second regardless of Engine.time_scale (the F2 dev 4x
# changes wall speed but not physics-frame count). MatchStats timestamps all
# events with sim_seconds() so analysis can compare matches that were run at
# different speeds.
var sim_ticks: int = 0
var _in_match: bool = false


func _physics_process(_delta: float) -> void:
	if _in_match:
		sim_ticks += 1


func sim_seconds() -> float:
	return float(sim_ticks) / 60.0


func reset_match() -> void:
	salvage = STARTING_SALVAGE
	sim_ticks = 0
	# Pick the match seed. CLI override (--seed=N) wins; otherwise Godot's
	# global randi() picks a fresh per-match seed. Either way, SimRng is
	# reseeded so all sim randomness starts from a known point.
	var override_seed: int = -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			var s: String = arg.substr(7)
			if s.is_valid_int():
				override_seed = int(s)
			break
	if override_seed >= 0:
		match_seed = override_seed
	else:
		match_seed = randi()
	if SimRng != null:
		SimRng.seed_with(match_seed)
	# SquadManager owns per-match state (squad registry, NATO name counter,
	# next-id allocator). Clear it so a new match starts at Alpha/id=1
	# without stale references from the previous run.
	if SquadManager != null:
		SquadManager.reset()
	# Projectiles in flight from the previous match must be freed before the
	# next one starts; otherwise they'd resolve damage in the new world.
	if ProjectileManager != null:
		ProjectileManager.cleanup_all()
	_in_match = true


func end_match() -> void:
	# Called by Main when win/defeat fires. Stops the sim clock so any
	# subsequent edge-wanderer spawns or animations don't advance sim time
	# into the post-match window.
	_in_match = false


func can_spend(amount: int) -> bool:
	return salvage >= amount


func spend(amount: int) -> bool:
	if salvage < amount:
		return false
	salvage -= amount
	return true


func add_salvage(amount: int) -> void:
	salvage += amount
