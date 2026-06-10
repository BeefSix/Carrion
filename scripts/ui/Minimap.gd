extends Control

# Minimap (SC console study, 2026-06-10). RENDER-ONLY — reads sim state,
# never writes it; refresh runs on a wall-time cadence in _process, which
# is sanctioned for UI (CLAUDE.md rule #2 applies to sim mutation).
#
# Layers, bottom to top:
#   1. Terrain underlay — one Image built from the town tile_grid at load
#      (192x192 px, 1:1 with tiles — the grid IS minimap-resolution).
#   2. Blips — buildings (squares), units (dots): player green, enemy
#      orange-red, zombies dull rust, lootables faint, infested sickly.
#   3. Camera view diamond — the iso viewport projected to world space.
# Click / drag: pan the camera to the clicked world position (SC behavior).

const WORLD := 6144.0
const REFRESH_SEC := 0.25  # 4 Hz blip refresh — SC1 cadence territory

const TILE_COLORS := {
	0: Color("23211e"), 1: Color("3a3733"), 2: Color("2a2825"),
	3: Color("2e2c29"), 4: Color("33312c"), 5: Color("31391f"),
	6: Color("3d3526"), 7: Color("4a3d28"), 8: Color("2c4020"),
	9: Color("3b3b3b"), 10: Color("44402f"),
}
const COL_PLAYER := Color(0.45, 0.95, 0.45)
const COL_ENEMY := Color(0.95, 0.45, 0.25)
const COL_ZOMBIE := Color(0.62, 0.30, 0.22)
const COL_LOOTABLE := Color(0.55, 0.52, 0.40)
const COL_INFESTED := Color(0.45, 0.60, 0.25)
const COL_VIEW := Color(0.9, 0.9, 0.75, 0.9)

var _terrain_tex: ImageTexture = null
var _refresh: float = 0.0
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_terrain()


func _build_terrain() -> void:
	var main = get_tree().current_scene
	if main == null:
		return
	var town: Dictionary = main.get("_town_data") if main.get("_town_data") != null else {}
	var grid: PackedByteArray = town.get("tile_grid", PackedByteArray())
	if grid.size() < 192 * 192:
		# No town yet (or non-Main scene): flat dark underlay.
		var img0 := Image.create(192, 192, false, Image.FORMAT_RGB8)
		img0.fill(Color("23211e"))
		_terrain_tex = ImageTexture.create_from_image(img0)
		return
	var img := Image.create(192, 192, false, Image.FORMAT_RGB8)
	for y in range(192):
		for x in range(192):
			img.set_pixel(x, y, TILE_COLORS.get(grid[y * 192 + x], Color("23211e")))
	_terrain_tex = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SEC
		queue_redraw()


func _world_to_map(p: Vector2) -> Vector2:
	return p / WORLD * size


func _draw() -> void:
	# Terrain.
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, size), false)
	# Buildings: lootables faint, infested sickly, player/enemy strong.
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var col: Color = COL_LOOTABLE
		if "is_infested" in b and b.is_infested:
			col = COL_INFESTED
		if b.is_in_group("player_buildings"):
			col = COL_PLAYER
		elif b.is_in_group("ai_buildings"):
			col = COL_ENEMY
		var mp: Vector2 = _world_to_map(b.position)
		var s: float = 3.0 if (b.is_in_group("player_buildings") or b.is_in_group("ai_buildings")) else 2.0
		draw_rect(Rect2(mp - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	# Units.
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		var col_u: Color
		if "faction" in u and u.faction == GameState.Faction.ZOMBIE:
			col_u = COL_ZOMBIE
		elif u.is_in_group("player_units"):
			col_u = COL_PLAYER
		else:
			col_u = COL_ENEMY
		var mp_u: Vector2 = _world_to_map(u.global_position)
		draw_rect(Rect2(mp_u - Vector2.ONE, Vector2(2, 2)), col_u)
	# Camera view diamond: project the four screen corners to world space.
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
		var tl: Vector2 = cam.get_screen_center_position() - vp_size * 0.5
		var pts := PackedVector2Array()
		for corner in [tl, tl + Vector2(vp_size.x, 0), tl + vp_size, tl + Vector2(0, vp_size.y), tl]:
			pts.append(_world_to_map(IsoView.screen_to_world(corner)))
		draw_polyline(pts, COL_VIEW, 1.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_pan_to(event.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan_to(event.position)
		accept_event()


func _pan_to(local: Vector2) -> void:
	var world: Vector2 = local / size * WORLD
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.position = IsoView.world_to_screen(world)
