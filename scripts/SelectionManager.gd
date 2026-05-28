class_name SelectionManager
extends Node2D

signal selection_changed(units: Array, building)

const DRAG_THRESHOLD_PX := 8.0
const WALL_GRID := 32.0
const WALL_COST := 25
const RUBBLE_TILE := 2

var _dragging := false
var _drag_start_world: Vector2
var _drag_start_screen: Vector2
var _selected_units: Array = []
var _selected_building = null

var _placing_wall := false
var _wall_builder = null


func _ready() -> void:
	add_to_group("selection_manager")


func start_wall_placement(builder) -> void:
	_placing_wall = true
	_wall_builder = builder
	queue_redraw()


func _cancel_wall_placement() -> void:
	_placing_wall = false
	_wall_builder = null
	queue_redraw()


func _confirm_wall_placement(world_pos: Vector2) -> void:
	if _wall_builder == null or not is_instance_valid(_wall_builder) or not _wall_builder.has_method("build_wall_at"):
		_cancel_wall_placement()
		return
	var snapped := _snap_to_grid(world_pos)
	if not _is_wall_placement_valid(snapped):
		return  # keep placement mode active so the player can pick another spot
	if not GameState.can_spend(WALL_COST):
		_cancel_wall_placement()
		return
	GameState.spend(WALL_COST)
	_wall_builder.build_wall_at(snapped)
	_cancel_wall_placement()


func _snap_to_grid(p: Vector2) -> Vector2:
	return (p / WALL_GRID).floor() * WALL_GRID + Vector2(WALL_GRID, WALL_GRID) * 0.5


func _is_wall_placement_valid(center: Vector2) -> bool:
	# Tile-type check: rubble is non-buildable; everything else (street, sidewalk, vegetation, dirt) is fine.
	var ground := get_tree().get_first_node_in_group("ground_tiles")
	if ground != null and ground.has_method("get_tile_type_at"):
		var t: int = ground.get_tile_type_at(center)
		if t == -1 or t == RUBBLE_TILE:
			return false
	# Building-overlap check: no overlap with any existing building footprint (adjacent edge contact is fine).
	var wall_rect := Rect2(center - Vector2(WALL_GRID, WALL_GRID) * 0.5, Vector2(WALL_GRID, WALL_GRID))
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if not ("size_pixels" in b):
			continue
		var bhalf: Vector2 = b.size_pixels * 0.5
		var brect := Rect2(b.position - bhalf, b.size_pixels)
		if wall_rect.intersects(brect):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _placing_wall:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_wall_placement(get_global_mouse_position())
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_wall_placement()
		elif event is InputEventMouseMotion:
			queue_redraw()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start_screen = event.position
				_drag_start_world = get_global_mouse_position()
				_dragging = true
			else:
				_finalize_selection(event.position, get_global_mouse_position())
				_dragging = false
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()


func _handle_right_click(world_pos: Vector2) -> void:
	var target_building = _find_building_at(world_pos)
	var target_lootable = null
	if target_building != null and target_building.is_in_group("lootable"):
		target_lootable = target_building
	var is_infested: bool = (target_lootable != null) and ("is_infested" in target_lootable) and target_lootable.is_infested
	var is_damaged: bool = (target_building != null) and ("current_hp" in target_building) and ("max_hp" in target_building) and target_building.current_hp < target_building.max_hp

	for u in _selected_units:
		if not is_instance_valid(u):
			continue
		if target_building != null and is_damaged and u.has_method("repair_at"):
			u.repair_at(target_building)
		elif target_lootable != null and is_infested and u.has_method("force_spawn_at"):
			u.force_spawn_at(target_lootable)
		elif target_lootable != null and u.has_method("gather_from"):
			u.gather_from(target_lootable)
		elif u.has_method("move_to"):
			u.move_to(world_pos)


func _find_building_at(world_pos: Vector2):
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_point(params)
	for hit in hits:
		var collider = hit.collider
		if collider != null and collider.is_in_group("buildings"):
			return collider
	return null


func _find_lootable_at(world_pos: Vector2):
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_point(params)
	for hit in hits:
		var collider = hit.collider
		if collider != null and collider.is_in_group("lootable"):
			return collider
	return null


func _finalize_selection(end_screen: Vector2, end_world: Vector2) -> void:
	var screen_distance := _drag_start_screen.distance_to(end_screen)
	if screen_distance < DRAG_THRESHOLD_PX:
		_click_select(end_world)
	else:
		_box_select(_drag_start_world, end_world)


func _click_select(world_pos: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_point(params)
	_clear_selection()
	for hit in hits:
		var collider = hit.collider
		if collider == null:
			continue
		if collider.is_in_group("buildings"):
			_select_building(collider)
			_emit_change()
			return
		if collider.is_in_group("player_units"):
			_add_to_selection(collider)
			_emit_change()
			return
	_emit_change()


func _box_select(corner_a: Vector2, corner_b: Vector2) -> void:
	var rect := Rect2(corner_a, corner_b - corner_a).abs()
	_clear_selection()
	for unit in get_tree().get_nodes_in_group("player_units"):
		if rect.has_point(unit.position):
			_add_to_selection(unit)
	_emit_change()


func _clear_selection() -> void:
	for u in _selected_units:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.set_selected(false)
	_selected_units.clear()
	if _selected_building != null and is_instance_valid(_selected_building):
		if _selected_building.has_method("set_selected"):
			_selected_building.set_selected(false)
	_selected_building = null


func _select_building(b) -> void:
	_selected_building = b
	if b.has_method("set_selected"):
		b.set_selected(true)


func _add_to_selection(u) -> void:
	if u not in _selected_units:
		_selected_units.append(u)
		if u.has_method("set_selected"):
			u.set_selected(true)


func _emit_change() -> void:
	selection_changed.emit(_selected_units.duplicate(), _selected_building)


func get_selected() -> Array:
	return _selected_units.duplicate()


func _draw() -> void:
	if _placing_wall:
		var center := _snap_to_grid(get_global_mouse_position())
		var half := Vector2(WALL_GRID, WALL_GRID) * 0.5
		var valid: bool = _is_wall_placement_valid(center) and GameState.can_spend(WALL_COST)
		var fill: Color = Color(0.4, 0.8, 0.4, 0.35) if valid else Color(0.9, 0.35, 0.3, 0.35)
		var border: Color = Color(0.6, 1.0, 0.6, 0.85) if valid else Color(1.0, 0.45, 0.4, 0.85)
		draw_rect(Rect2(center - half, Vector2(WALL_GRID, WALL_GRID)), fill, true)
		draw_rect(Rect2(center - half, Vector2(WALL_GRID, WALL_GRID)), border, false, 2.0)
	if _dragging:
		var current_world := get_global_mouse_position()
		var rect := Rect2(_drag_start_world, current_world - _drag_start_world).abs()
		draw_rect(rect, Color(1, 1, 0.4, 0.18), true)
		draw_rect(rect, Color(1, 1, 0.4, 0.7), false, 2.0)
