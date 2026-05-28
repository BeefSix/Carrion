class_name SelectionManager
extends Node2D

signal selection_changed(units: Array, building)

const DRAG_THRESHOLD_PX := 8.0

var _dragging := false
var _drag_start_world: Vector2
var _drag_start_screen: Vector2
var _selected_units: Array = []
var _selected_building = null


func _ready() -> void:
	add_to_group("selection_manager")


func _unhandled_input(event: InputEvent) -> void:
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
	var target_lootable = _find_lootable_at(world_pos)
	var is_infested: bool = (target_lootable != null) and ("is_infested" in target_lootable) and target_lootable.is_infested
	for u in _selected_units:
		if not is_instance_valid(u):
			continue
		if target_lootable != null and is_infested and u.has_method("force_spawn_at"):
			u.force_spawn_at(target_lootable)
		elif target_lootable != null and u.has_method("gather_from"):
			u.gather_from(target_lootable)
		elif u.has_method("move_to"):
			u.move_to(world_pos)


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
	if _dragging:
		var current_world := get_global_mouse_position()
		var rect := Rect2(_drag_start_world, current_world - _drag_start_world).abs()
		draw_rect(rect, Color(1, 1, 0.4, 0.18), true)
		draw_rect(rect, Color(1, 1, 0.4, 0.7), false, 2.0)
