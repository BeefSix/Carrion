class_name Lootable
extends "res://scripts/Building.gd"

@export var starting_salvage: int = 200

var remaining_salvage: int = 0


func _ready() -> void:
	super._ready()
	remaining_salvage = starting_salvage
	add_to_group("lootable")


func take_salvage(amount: int) -> int:
	var taken: int = min(amount, remaining_salvage)
	remaining_salvage -= taken
	if remaining_salvage <= 0:
		queue_free()
	return taken
