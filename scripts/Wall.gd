class_name Wall
extends "res://scripts/Building.gd"

# Survivor wall segment. Renders as an upright iso barrier - half-tile width
# in world coords (the 32x32 footprint), but a tall vertical surface in screen.
# Overrides Building._draw entirely because walls don't have a flat-roofed
# building form; they're barriers.
#
# Auto-connect logic stays - neighboring walls in the cardinal directions
# trigger redraws on each other so the visible structure reads as a continuous
# barrier when segments touch.

const DESTROY_NOISE := 50.0
const TILE_PX := 32.0
const NEIGHBOR_EPSILON := 6.0
const WALL_SCREEN_HEIGHT := 24.0


func _ready() -> void:
	super._ready()
	add_to_group("walls")
	_refresh_neighbors()


func _die() -> void:
	Noise.emit(global_position, DESTROY_NOISE)
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


func _draw() -> void:
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	# 32x32 footprint, projected to iso corners.
	var hw: float = TILE_PX * 0.5
	var nw: Vector2 = IsoView.world_to_screen(Vector2(-hw, -hw))
	var ne: Vector2 = IsoView.world_to_screen(Vector2(hw, -hw))
	var se: Vector2 = IsoView.world_to_screen(Vector2(hw, hw))
	var sw: Vector2 = IsoView.world_to_screen(Vector2(-hw, hw))

	var nw_top: Vector2 = nw + Vector2(0.0, -WALL_SCREEN_HEIGHT)
	var ne_top: Vector2 = ne + Vector2(0.0, -WALL_SCREEN_HEIGHT)
	var se_top: Vector2 = se + Vector2(0.0, -WALL_SCREEN_HEIGHT)
	var sw_top: Vector2 = sw + Vector2(0.0, -WALL_SCREEN_HEIGHT)

	# South face
	draw_colored_polygon(PackedVector2Array([sw, se, se_top, sw_top]), body_color)
	# East face
	draw_colored_polygon(PackedVector2Array([se, ne, ne_top, se_top]), body_color.darkened(0.2))
	# Top cap
	draw_colored_polygon(PackedVector2Array([nw_top, ne_top, se_top, sw_top]), body_color.lightened(0.15))

	# Edges
	var edge: Color = body_color.darkened(0.4)
	draw_line(sw, se, edge, 1.0)
	draw_line(se, ne, edge, 1.0)
	draw_line(sw, sw_top, edge, 1.0)
	draw_line(se, se_top, edge, 1.0)
	draw_line(ne, ne_top, edge, 1.0)
	draw_line(nw_top, ne_top, edge, 1.0)
	draw_line(ne_top, se_top, edge, 1.0)
	draw_line(se_top, sw_top, edge, 1.0)
	draw_line(sw_top, nw_top, edge, 1.0)

	if selected:
		draw_polyline(PackedVector2Array([nw_top, ne_top, se_top, sw_top, nw_top]), Color(1, 1, 0.4), 1.6, true)

	# HP bar above
	if current_hp < max_hp:
		var bar_w: float = 28.0
		var bar_y: float = nw_top.y - 8.0
		var bar_x: float = -bar_w * 0.5
		draw_rect(Rect2(bar_x, bar_y, bar_w, 2.5), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		draw_rect(Rect2(bar_x, bar_y, bar_w * fill_ratio, 2.5), Color(0.35, 0.65, 0.3))
