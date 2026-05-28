class_name Wall
extends "res://scripts/Building.gd"

const DESTROY_NOISE := 50.0


func _ready() -> void:
	super._ready()
	add_to_group("walls")


func _die() -> void:
	var nf = get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, DESTROY_NOISE)
	super._die()


func _draw_building_icon() -> void:
	# Brick hatch lines so a wall reads differently from a structure block.
	draw_line(Vector2(-16, -5), Vector2(16, -5), Color(0.3, 0.28, 0.24), 1.0)
	draw_line(Vector2(-16, 5), Vector2(16, 5), Color(0.3, 0.28, 0.24), 1.0)
	draw_line(Vector2(0, -16), Vector2(0, -5), Color(0.3, 0.28, 0.24), 1.0)
	draw_line(Vector2(-8, 5), Vector2(-8, 16), Color(0.3, 0.28, 0.24), 1.0)
	draw_line(Vector2(8, 5), Vector2(8, 16), Color(0.3, 0.28, 0.24), 1.0)
