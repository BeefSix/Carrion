extends Node2D

const CELL_SIZE := 512.0
const GRID_DIM := 5
const MAP_SIZE := Vector2(2560, 2560)
const NOISE_DECAY_RATE := 5.0
const NOISE_AOE_RADIUS := 1600.0
const HORDE_THRESHOLD := 200.0
const HORDE_SIZE := 15
const HORDE_COOLDOWN := 30.0
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")

var _cells: Array = []
var _cell_cooldowns: Array = []
var _debug_visible := false


func _ready() -> void:
	add_to_group("noise_field")
	for x in range(GRID_DIM):
		var col: Array = []
		var col_cd: Array = []
		for y in range(GRID_DIM):
			col.append(0.0)
			col_cd.append(0.0)
		_cells.append(col)
		_cell_cooldowns.append(col_cd)


func add_noise(world_pos: Vector2, magnitude: float) -> void:
	for x in range(GRID_DIM):
		for y in range(GRID_DIM):
			var cell_center := Vector2(x * CELL_SIZE + CELL_SIZE * 0.5, y * CELL_SIZE + CELL_SIZE * 0.5)
			if cell_center.distance_to(world_pos) <= NOISE_AOE_RADIUS:
				_cells[x][y] += magnitude


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		_debug_visible = not _debug_visible
		queue_redraw()


func _process(delta: float) -> void:
	var decay: float = NOISE_DECAY_RATE * delta
	for x in range(GRID_DIM):
		for y in range(GRID_DIM):
			if _cells[x][y] > 0.0:
				_cells[x][y] = max(0.0, _cells[x][y] - decay)
			if _cell_cooldowns[x][y] > 0.0:
				_cell_cooldowns[x][y] = max(0.0, _cell_cooldowns[x][y] - delta)
			if _cells[x][y] >= HORDE_THRESHOLD and _cell_cooldowns[x][y] <= 0.0:
				_trigger_horde(x, y)
				_cells[x][y] = 0.0
				_cell_cooldowns[x][y] = HORDE_COOLDOWN
	if _debug_visible:
		queue_redraw()


func _trigger_horde(cx: int, cy: int) -> void:
	var target := Vector2(cx * CELL_SIZE + CELL_SIZE * 0.5, cy * CELL_SIZE + CELL_SIZE * 0.5)
	var spawn_pos := _pick_edge_spawn(target)
	for i in range(HORDE_SIZE):
		var jitter := Vector2(randf_range(-60, 60), randf_range(-60, 60))
		var s = SHAMBLER_SCENE.instantiate()
		s.position = spawn_pos + jitter
		get_parent().add_child(s)
		if s.has_method("investigate"):
			s.investigate(target)


func _pick_edge_spawn(target: Vector2) -> Vector2:
	var candidates := [
		Vector2(20.0, target.y),
		Vector2(MAP_SIZE.x - 20.0, target.y),
		Vector2(target.x, 20.0),
		Vector2(target.x, MAP_SIZE.y - 20.0),
	]
	var best: Vector2 = candidates[0]
	var best_dist := INF
	for c in candidates:
		var d: float = c.distance_to(target)
		if d < best_dist:
			best_dist = d
			best = c
	return best


func _draw() -> void:
	if not _debug_visible:
		return
	for x in range(GRID_DIM):
		for y in range(GRID_DIM):
			var noise: float = _cells[x][y]
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			if noise > 0.0:
				var intensity: float = clamp(noise / HORDE_THRESHOLD, 0.0, 1.0)
				draw_rect(rect, Color(1, 0.4, 0.1, intensity * 0.45), true)
			draw_rect(rect, Color(1, 0.4, 0.1, 0.25), false, 1.0)
