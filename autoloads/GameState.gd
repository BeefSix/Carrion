extends Node

signal salvage_changed(new_value: int)

var salvage: int = 200:
	set(value):
		salvage = value
		salvage_changed.emit(value)


func can_spend(amount: int) -> bool:
	return salvage >= amount


func spend(amount: int) -> bool:
	if salvage < amount:
		return false
	salvage -= amount
	return true


func add_salvage(amount: int) -> void:
	salvage += amount
