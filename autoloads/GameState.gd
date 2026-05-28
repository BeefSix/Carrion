extends Node

signal salvage_changed(new_value: int)

enum Faction { MILITARY, TRIBAL }

const STARTING_SALVAGE := 200

var salvage: int = STARTING_SALVAGE:
	set(value):
		salvage = value
		salvage_changed.emit(value)

var player_faction: Faction = Faction.MILITARY


func reset_match() -> void:
	salvage = STARTING_SALVAGE


func can_spend(amount: int) -> bool:
	return salvage >= amount


func spend(amount: int) -> bool:
	if salvage < amount:
		return false
	salvage -= amount
	return true


func add_salvage(amount: int) -> void:
	salvage += amount
