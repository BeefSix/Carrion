extends Node

signal salvage_changed(new_value: int)

enum Faction { MILITARY, TRIBAL, SURVIVOR }

const STARTING_SALVAGE := 200

var salvage: int = STARTING_SALVAGE:
	set(value):
		salvage = value
		salvage_changed.emit(value)

var player_faction: Faction = Faction.MILITARY
var ai_enabled: bool = false


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
