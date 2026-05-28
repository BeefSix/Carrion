class_name Wall
extends "res://scripts/Building.gd"

const DESTROY_NOISE := 50.0
const TILE_PX := 32.0
const NEIGHBOR_EPSILON := 6.0
const CAP_THICKNESS := 3.0
const CAP_COLOR := Color(0.62, 0.58, 0.50)
const TOP_STRIP_COLOR := Color(0.32, 0.30, 0.26)


func _ready() -> void:
	super._ready()
	add_to_group("walls")
	_refresh_neighbors()


func _die() -> void:
	var nf = get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(global_position, DESTROY_NOISE)
	_refresh_neighbors()
	super._die()


func _has_wall_neighbor(direction: Vector2) -> bool:
	var query_pos: Vector2 = position + direction * TILE_PX
	for w in get_tree().get_nodes_in_group("walls"):
		if w == self or not is_instance_valid(w):
			continue
		if w.position.distance_to(query_pos) < NEIGHBOR_EPSILON:
			return true
	return false


func _refresh_neighbors() -> void:
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var query_pos: Vector2 = position + d * TILE_PX
		for w in get_tree().get_nodes_in_group("walls"):
			if w == self or not is_instance_valid(w):
				continue
			if w.position.distance_to(query_pos) < NEIGHBOR_EPSILON:
				w.queue_redraw()


func _draw_building_icon() -> void:
	# Continuous "top edge" strip - reads as one wall line when adjacent walls touch.
	draw_rect(Rect2(Vector2(-16, -16), Vector2(32, 4)), TOP_STRIP_COLOR)

	# Edge caps where there's no neighbor: wall ends look like ends.
	var has_left: bool = _has_wall_neighbor(Vector2.LEFT)
	var has_right: bool = _has_wall_neighbor(Vector2.RIGHT)
	var has_up: bool = _has_wall_neighbor(Vector2.UP)
	var has_down: bool = _has_wall_neighbor(Vector2.DOWN)

	if not has_left:
		draw_rect(Rect2(Vector2(-16, -16), Vector2(CAP_THICKNESS, 32)), CAP_COLOR)
	if not has_right:
		draw_rect(Rect2(Vector2(16 - CAP_THICKNESS, -16), Vector2(CAP_THICKNESS, 32)), CAP_COLOR)
	if not has_up:
		draw_rect(Rect2(Vector2(-16, -16), Vector2(32, CAP_THICKNESS)), CAP_COLOR)
	if not has_down:
		draw_rect(Rect2(Vector2(-16, 16 - CAP_THICKNESS), Vector2(32, CAP_THICKNESS)), CAP_COLOR)
