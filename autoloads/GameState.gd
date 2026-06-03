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


func reset_match() -> void:
	salvage = STARTING_SALVAGE
	# SquadManager owns per-match state (squad registry, NATO name counter,
	# next-id allocator). Clear it so a new match starts at Alpha/id=1
	# without stale references from the previous run.
	if SquadManager != null:
		SquadManager.reset()
	# Projectiles in flight from the previous match must be freed before the
	# next one starts; otherwise they'd resolve damage in the new world.
	if ProjectileManager != null:
		ProjectileManager.cleanup_all()


func can_spend(amount: int) -> bool:
	return salvage >= amount


func spend(amount: int) -> bool:
	if salvage < amount:
		return false
	salvage -= amount
	return true


func add_salvage(amount: int) -> void:
	salvage += amount
