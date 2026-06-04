extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const TOWN_PLANNER_SCRIPT := preload("res://scripts/maps/TownPlanner.gd")
const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const SH_SCENE := preload("res://scenes/buildings/SettlementHub.tscn")
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const WIN_OVERLAY_SCENE := preload("res://scenes/WinOverlay.tscn")
const MAP_SIZE := Vector2(6144, 6144)
const DEV_SPEED := 4.0
const DEV_NOISE_INJECT := 100.0

# Edge wanderer: low-rate ambient zombie drift in from off-map.
const EDGE_SPAWN_INTERVAL := 90.0
const EDGE_INSET := 60.0
const EDGE_SPAWN_KEEPOUT := 1200.0  # avoid dumping wanderers on top of the player corner

# Per-faction corner spawns. Tile (18, 18) center inside the rubble edge band; clear zone
# is the surrounding 12x12 tiles, big enough to drop HQ + a few small buildings + walls.
# Per-faction corner spawns. Players land inside their residential zone with
# a 16-tile clear zone around the HQ. Per PZ town-layout spec: NW + SE are
# residential corners (player starts). NE corner is medical/security
# (contested), SW corner is industrial (contested).
const SPAWN_NW := Vector2(768, 768)    # tile (24, 24) - NW residential
const SPAWN_NE := Vector2(5120, 768)   # tile (160, 24) - NE medical
const SPAWN_SW := Vector2(768, 5120)   # tile (24, 160) - SW industrial
const SPAWN_SE := Vector2(5120, 5120)  # tile (160, 160) - SE residential

# PZ town-layout hand-placed Lootables. ~70 buildings across six zones:
#   NW residential (20 houses)
#   SE residential (20 houses)
#   Downtown commercial + civic (10)
#   SW industrial (8 warehouses)
#   NE medical/security (6 institutional)
#   Wilderness rural (6 farmhouses)
# Positions are world pixel centers. Footprints come from Lootable.FOOTPRINTS
# keyed by type (2x2 residential, 3x2 commercial, 3x3 institutional, etc.).
const NEIGHBORHOOD_LAYOUT := [
	# NW Residential - 5x4 grid west of secondary road at x=56, north of secondary at y=56.
	{ "pos": Vector2(1216, 1216), "type": "residential" },
	{ "pos": Vector2(1344, 1216), "type": "residential" },
	{ "pos": Vector2(1472, 1216), "type": "residential" },
	{ "pos": Vector2(1600, 1216), "type": "residential" },
	{ "pos": Vector2(1728, 1216), "type": "residential" },
	{ "pos": Vector2(1216, 1344), "type": "residential" },
	{ "pos": Vector2(1344, 1344), "type": "residential" },
	{ "pos": Vector2(1472, 1344), "type": "residential" },
	{ "pos": Vector2(1600, 1344), "type": "residential" },
	{ "pos": Vector2(1728, 1344), "type": "residential" },
	{ "pos": Vector2(1216, 1472), "type": "residential" },
	{ "pos": Vector2(1344, 1472), "type": "residential" },
	{ "pos": Vector2(1472, 1472), "type": "residential" },
	{ "pos": Vector2(1600, 1472), "type": "residential" },
	{ "pos": Vector2(1728, 1472), "type": "residential" },
	{ "pos": Vector2(1216, 1600), "type": "residential" },
	{ "pos": Vector2(1344, 1600), "type": "residential" },
	{ "pos": Vector2(1472, 1600), "type": "residential" },
	{ "pos": Vector2(1600, 1600), "type": "residential" },
	{ "pos": Vector2(1728, 1600), "type": "residential" },

	# SE Residential - 5x4 grid mirrored from NW (north-west of player 2 spawn).
	{ "pos": Vector2(4416, 4416), "type": "residential" },
	{ "pos": Vector2(4544, 4416), "type": "residential" },
	{ "pos": Vector2(4672, 4416), "type": "residential" },
	{ "pos": Vector2(4800, 4416), "type": "residential" },
	{ "pos": Vector2(4928, 4416), "type": "residential" },
	{ "pos": Vector2(4416, 4544), "type": "residential" },
	{ "pos": Vector2(4544, 4544), "type": "residential" },
	{ "pos": Vector2(4672, 4544), "type": "residential" },
	{ "pos": Vector2(4800, 4544), "type": "residential" },
	{ "pos": Vector2(4928, 4544), "type": "residential" },
	{ "pos": Vector2(4416, 4672), "type": "residential" },
	{ "pos": Vector2(4544, 4672), "type": "residential" },
	{ "pos": Vector2(4672, 4672), "type": "residential" },
	{ "pos": Vector2(4800, 4672), "type": "residential" },
	{ "pos": Vector2(4928, 4672), "type": "residential" },
	{ "pos": Vector2(4416, 4800), "type": "residential" },
	{ "pos": Vector2(4544, 4800), "type": "residential" },
	{ "pos": Vector2(4672, 4800), "type": "residential" },
	{ "pos": Vector2(4800, 4800), "type": "residential" },
	{ "pos": Vector2(4928, 4800), "type": "residential" },

	# Downtown commercial strip - 8 stores along the main road, north and south.
	{ "pos": Vector2(2752, 2784), "type": "commercial" },
	{ "pos": Vector2(2880, 2784), "type": "commercial" },
	{ "pos": Vector2(3264, 2784), "type": "commercial" },
	{ "pos": Vector2(3392, 2784), "type": "commercial" },
	{ "pos": Vector2(2752, 3360), "type": "commercial" },
	{ "pos": Vector2(2880, 3360), "type": "commercial" },
	{ "pos": Vector2(3264, 3360), "type": "commercial" },
	{ "pos": Vector2(3392, 3360), "type": "commercial" },
	# Downtown civic - school, government, plaza
	{ "pos": Vector2(2752, 3072), "type": "civic" },
	{ "pos": Vector2(3392, 3072), "type": "civic" },

	# SW industrial - 8 warehouses in two rows
	{ "pos": Vector2(1024, 4416), "type": "industrial" },
	{ "pos": Vector2(1248, 4416), "type": "industrial" },
	{ "pos": Vector2(1472, 4416), "type": "industrial" },
	{ "pos": Vector2(1696, 4416), "type": "industrial" },
	{ "pos": Vector2(1024, 4672), "type": "industrial" },
	{ "pos": Vector2(1248, 4672), "type": "industrial" },
	{ "pos": Vector2(1472, 4672), "type": "industrial" },
	{ "pos": Vector2(1696, 4672), "type": "industrial" },

	# NE medical/security - 2 hospitals, 2 police, 2 mixed
	{ "pos": Vector2(4448, 1216), "type": "medical" },
	{ "pos": Vector2(4672, 1216), "type": "medical" },
	{ "pos": Vector2(4448, 1440), "type": "security" },
	{ "pos": Vector2(4672, 1440), "type": "security" },
	{ "pos": Vector2(4448, 1664), "type": "medical" },
	{ "pos": Vector2(4672, 1664), "type": "security" },

	# Wilderness rural - 6 isolated farmhouses at the edges of the map
	{ "pos": Vector2(384, 384), "type": "residential" },
	{ "pos": Vector2(5760, 384), "type": "residential" },
	{ "pos": Vector2(384, 5760), "type": "residential" },
	{ "pos": Vector2(5760, 5760), "type": "residential" },
	{ "pos": Vector2(3072, 320), "type": "residential" },
	{ "pos": Vector2(3072, 5824), "type": "residential" },
]

const INFESTED_RATE_BY_TYPE := {
	"residential": 0.4,
	"commercial": 0.3,
	"industrial": 0.5,
	"medical": 1.0,
	"security": 1.0,
	"civic": 0.5,
}


var _edge_timer := 0.0
var _player_hq: Node2D = null
var _opposing_hq: Node2D = null
var _match_ended: bool = false
var _win_overlay: CanvasLayer = null


var _town_data: Dictionary = {}
# Cached 192x192 ground tile grid for nav-mesh road preference. Stored after
# the tile grid is applied so _rebake_navigation can build a road sub-region.
var _tile_grid: PackedByteArray


func _ready() -> void:
	GameState.reset_match()
	# Dev CLI override: --ridley flag (after Godot's -- separator) forces the
	# image-to-map PoC path. Lets headless testing skip the TitleScreen.
	var user_args := OS.get_cmdline_user_args()
	if "--ridley" in user_args:
		GameState.custom_map_path = "res://assets/maps/ridley_data.json"
	# Image-to-map PoC: when GameState.custom_map_path is set, load that JSON
	# instead of running TownPlanner. The image is rendered as an iso-projected
	# Polygon2D background covering the world's diamond view space.
	if GameState.custom_map_path != "":
		_load_custom_map(GameState.custom_map_path)
	else:
		# Standard procedural town generation. TownPlanner runs its 12-step
		# pipeline and hands back tile_grid + lots + buildings + lootables.
		var planner = TOWN_PLANNER_SCRIPT.new()
		_town_data = planner.plan_town()
		_tile_grid = _town_data["tile_grid"]
		$GroundTiles.apply_tile_grid(_tile_grid)
	_spawn_hq()
	_spawn_lootables()
	_rebake_navigation()
	_center_camera_on_spawn()
	if GameState.ai_enabled:
		_spawn_ai_opponent()
	else:
		_spawn_inert_opposing_hq()
	_install_win_overlay()
	# --stress-rifleman flag: spawn 2 Riflemen and command them to march to
	# the opposite corner. Used to reproduce the user's "2 Riflemen at 90s
	# absolute bog" report headlessly so we can capture PerfProbe data.
	if "--stress-rifleman" in user_args:
		call_deferred("_run_stress_rifleman")


func _run_stress_rifleman() -> void:
	print("[Stress] Spawning 2 Riflemen and marching to opposite corner")
	var rifleman_scene: PackedScene = load("res://scenes/units/Rifleman.tscn")
	if rifleman_scene == null:
		print("[Stress] Failed to load Rifleman scene")
		return
	var spawn := _get_spawn_position()
	var dest := _get_ai_spawn_position()
	for i in range(2):
		var r = rifleman_scene.instantiate()
		r.position = spawn + Vector2(40 * i, 40 * i)
		add_child(r)
		r.add_to_group("player_units")
		# Defer move_to so the unit's _ready has run and nav agent is wired.
		r.call_deferred("move_to", dest)
	print("[Stress] Spawn done at %s, dest %s" % [spawn, dest])


# Image-to-map: load extracted map data + render the source image as
# iso-projected background. Maps image categories to GroundTiles indices and
# adapts the building list into the _town_data["lootables"] shape that
# _spawn_lootables already consumes.
func _load_custom_map(json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_warning("Custom map JSON not found: %s. Falling back to procedural." % json_path)
		var planner = TOWN_PLANNER_SCRIPT.new()
		_town_data = planner.plan_town()
		_tile_grid = _town_data["tile_grid"]
		$GroundTiles.apply_tile_grid(_tile_grid)
		return
	var raw: String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(raw)
	if data == null:
		push_warning("Custom map JSON parse failed. Falling back to procedural.")
		var planner2 = TOWN_PLANNER_SCRIPT.new()
		_town_data = planner2.plan_town()
		$GroundTiles.apply_tile_grid(_town_data["tile_grid"])
		return

	# Image category -> GroundTiles atlas index. Categories from the Python
	# pipeline: 0=open, 1=road, 2=parking, 3=building, 4=athletic, 5=water,
	# 6=rail. GroundTiles indices: see scripts/GroundTiles.gd TILE_COLORS.
	const CATEGORY_TO_GROUND_TILE := {
		0: 5,   # open -> yard
		1: 2,   # road -> secondary road
		2: 4,   # parking -> parking lot
		3: 6,   # building -> bare ground (actual building footprints layered on top)
		4: 5,   # athletic -> yard (green)
		5: 8,   # water -> vegetation (placeholder; no water tile in atlas)
		6: 7,   # rail -> dirt road
	}
	const TILE_COUNT := 192
	var tile_rows: Array = data.get("tile_grid", [])
	var grid := PackedByteArray()
	grid.resize(TILE_COUNT * TILE_COUNT)
	for y in range(TILE_COUNT):
		if y >= tile_rows.size():
			continue
		var row: String = tile_rows[y]
		for x in range(TILE_COUNT):
			if x >= row.length():
				continue
			var cat: int = int(row[x])
			var tile_idx: int = CATEGORY_TO_GROUND_TILE.get(cat, 5)
			grid[x + y * TILE_COUNT] = tile_idx
	_tile_grid = grid
	$GroundTiles.apply_tile_grid(grid)

	# Adapt the building list into the lootables shape (_spawn_lootables
	# expects entries with "pos" and "type"). Add type-based loot tagging.
	var lootables: Array = []
	for b in data.get("buildings", []):
		lootables.append({
			"pos": Vector2(b["pos"][0], b["pos"][1]),
			"type": b.get("type", "residential"),
		})
	_town_data = {"lootables": lootables}
	print("[CustomMap] Loaded %s: %d buildings, tile_grid %dx%d" % [json_path, lootables.size(), TILE_COUNT, TILE_COUNT])

	# Render the source image as the visible map background. Polygon2D with
	# diamond vertices in iso screen space and rectangle UVs into the
	# 2048x2048 source - this maps the square image onto the iso-projected
	# world view so it visually aligns with the gameplay grid.
	var source_path: String = data.get("source_image", "")
	if source_path != "":
		_install_image_background(source_path)


func _install_image_background(image_path: String) -> void:
	# Load via Image API rather than the resource system - the latter requires
	# Godot to have imported the .import sidecar, which the asset pipeline does
	# on editor open. For PoC we load the raw bytes at runtime so this works
	# fresh-from-clone without an editor pass.
	var img := Image.new()
	var abs_path: String = image_path.replace("res://", "")
	var err: int = img.load(ProjectSettings.globalize_path("res://" + abs_path))
	if err != OK:
		push_warning("Background image load failed (%d): %s" % [err, image_path])
		return
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("Background image texture build failed: %s" % image_path)
		return
	var img_size: Vector2 = tex.get_size()
	var poly := Polygon2D.new()
	poly.name = "RidleyBackground"
	poly.texture = tex
	# Iso projection of world (0,0)-(6144,6144) gives a diamond:
	#   world (0,0)        -> iso (0, 0)
	#   world (W,0)        -> iso (W, W*0.75)
	#   world (W,W)        -> iso (0, W*1.5)
	#   world (0,W)        -> iso (-W, W*0.75)
	# We tile the image rectangle onto this diamond via the UV mapping below.
	var W: float = MAP_SIZE.x
	poly.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(W, W * 0.75),
		Vector2(0, W * 1.5),
		Vector2(-W, W * 0.75),
	])
	poly.uv = PackedVector2Array([
		Vector2(0, 0),                          # top of diamond -> top-left of image
		Vector2(img_size.x, 0),                 # right of diamond -> top-right
		Vector2(img_size.x, img_size.y),        # bottom of diamond -> bottom-right
		Vector2(0, img_size.y),                 # left of diamond -> bottom-left
	])
	poly.z_index = -1000  # render below everything else
	add_child(poly)
	# Hide the procedural ground polygon and tile rendering so the image shows.
	if has_node("Ground"):
		$Ground.visible = false
	if has_node("GroundTiles"):
		$GroundTiles.modulate = Color(1, 1, 1, 0.0)  # invisible but still queryable for get_tile_type_at


func _spawn_ai_opponent() -> void:
	var ai_scene := load("res://scripts/ai/AIController.gd") as Script
	if ai_scene == null:
		return
	var ai = ai_scene.new()
	ai.faction = GameState.Faction.MILITARY
	ai.spawn_position = _get_ai_spawn_position()
	ai.enemy_hq_position = _get_spawn_position()
	add_child(ai)


func _spawn_inert_opposing_hq() -> void:
	var scene: PackedScene = _opposing_inert_scene()
	if scene == null:
		return
	var hq: Node2D = scene.instantiate()
	hq.position = _get_ai_spawn_position()
	add_child(hq)
	hq.add_to_group("ai_buildings")
	_opposing_hq = hq


func _opposing_inert_scene() -> PackedScene:
	match GameState.player_faction:
		GameState.Faction.MILITARY:
			return TC_SCENE
		GameState.Faction.TRIBAL:
			return CP_SCENE
		GameState.Faction.SURVIVOR:
			return CP_SCENE
		_:
			return CP_SCENE


func set_opposing_hq(hq: Node2D) -> void:
	_opposing_hq = hq


func _install_win_overlay() -> void:
	_win_overlay = WIN_OVERLAY_SCENE.instantiate()
	add_child(_win_overlay)


func _check_win_conditions() -> void:
	if _match_ended:
		return
	if _player_hq != null and not is_instance_valid(_player_hq):
		_match_ended = true
		if _win_overlay != null:
			_win_overlay.show_defeat()
		return
	if _opposing_hq != null and not is_instance_valid(_opposing_hq):
		_match_ended = true
		if _win_overlay != null:
			_win_overlay.show_victory()


func _get_ai_spawn_position() -> Vector2:
	match GameState.player_faction:
		GameState.Faction.MILITARY:
			return SPAWN_SE
		GameState.Faction.TRIBAL:
			return SPAWN_NW
		GameState.Faction.SURVIVOR:
			return SPAWN_NE
		_:
			return SPAWN_SE


func _process(delta: float) -> void:
	_edge_timer += delta
	if _edge_timer >= EDGE_SPAWN_INTERVAL:
		_edge_timer = 0.0
		_spawn_edge_wanderer()
	_check_win_conditions()


func _spawn_edge_wanderer() -> void:
	var spawn_pos := _get_spawn_position()
	var pos := Vector2.ZERO
	for attempt in range(8):
		var edge: int = randi() % 4
		match edge:
			0:
				pos = Vector2(randf_range(EDGE_INSET, MAP_SIZE.x - EDGE_INSET), EDGE_INSET)
			1:
				pos = Vector2(MAP_SIZE.x - EDGE_INSET, randf_range(EDGE_INSET, MAP_SIZE.y - EDGE_INSET))
			2:
				pos = Vector2(randf_range(EDGE_INSET, MAP_SIZE.x - EDGE_INSET), MAP_SIZE.y - EDGE_INSET)
			_:
				pos = Vector2(EDGE_INSET, randf_range(EDGE_INSET, MAP_SIZE.y - EDGE_INSET))
		if pos.distance_to(spawn_pos) >= EDGE_SPAWN_KEEPOUT:
			break
	var s = SHAMBLER_SCENE.instantiate()
	s.position = pos
	add_child(s)


func _get_spawn_position() -> Vector2:
	match GameState.player_faction:
		GameState.Faction.MILITARY:
			return SPAWN_NW
		GameState.Faction.TRIBAL:
			return SPAWN_SE
		GameState.Faction.SURVIVOR:
			return SPAWN_SW
		_:
			return SPAWN_NW


func _center_camera_on_spawn() -> void:
	# Camera lives in iso screen-space (tiles now render iso via TileMapLayer's
	# TILE_SHAPE_ISOMETRIC). Project the world-coord spawn to its iso position
	# so the camera frames the correct corner of the angled map.
	if has_node("Camera"):
		$Camera.position = IsoView.world_to_screen(_get_spawn_position())


func rebake_navigation() -> void:
	_rebake_navigation()


func _rebake_navigation() -> void:
	# Building obstruction outlines used by both the main nav region and the
	# road sub-region. Computed once.
	var building_outlines: Array = []
	var pad := 4.0
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_in_group("walls"):
			continue
		if not ("size_pixels" in b):
			continue
		var half: Vector2 = b.size_pixels * 0.5
		var p: Vector2 = b.position
		building_outlines.append(PackedVector2Array([
			p + Vector2(-half.x - pad, -half.y - pad),
			p + Vector2(half.x + pad, -half.y - pad),
			p + Vector2(half.x + pad, half.y + pad),
			p + Vector2(-half.x - pad, half.y + pad),
		]))

	# Main nav region: whole map walkable, default travel cost.
	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = 12.0
	var outer := PackedVector2Array([
		Vector2(0, 0),
		Vector2(MAP_SIZE.x, 0),
		Vector2(MAP_SIZE.x, MAP_SIZE.y),
		Vector2(0, MAP_SIZE.y),
	])
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(outer)
	for outline in building_outlines:
		source.add_obstruction_outline(outline)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source, Callable())
	$NavRegion.navigation_polygon = nav_poly

	# Road sub-region: a second NavigationRegion2D covering only road tiles,
	# with lower travel_cost. The pathfinder treats it as a cheaper overlay,
	# so optimal paths route through the road grid even when a direct line
	# across yards would be shorter geometrically. Falls back gracefully if
	# _tile_grid is empty (custom map without ground-tile data).
	_setup_road_region(building_outlines)


# Ground-tile indices that count as "road" for navigation preference. From
# GroundTiles.TILE_COLORS: 0=main road, 1=sidewalk, 2=secondary road,
# 3=side street, 4=parking lot, 7=dirt road. Yards (5), bare ground (6),
# vegetation (8), rubble (9), fence (10) stay normal cost.
const ROAD_TILE_INDICES := [0, 1, 2, 3, 4, 7]
const TILE_GRID_W := 192
const TILE_GRID_PX := 32


func _setup_road_region(building_outlines: Array) -> void:
	if _tile_grid.is_empty():
		return
	var road_node: NavigationRegion2D = get_node_or_null("RoadRegion") as NavigationRegion2D
	if road_node == null:
		road_node = NavigationRegion2D.new()
		road_node.name = "RoadRegion"
		# Lower travel cost than the main region's default 1.0 - pathfinder
		# prefers this overlay where it overlaps with the main region.
		road_node.travel_cost = 0.5
		add_child(road_node)

	var road_poly := NavigationPolygon.new()
	road_poly.agent_radius = 12.0
	var source := NavigationMeshSourceGeometryData2D.new()

	# Row-span merge: emit one rect per contiguous run of road tiles in a row.
	# 192*5 = ~1000 outlines vs ~10000 if we emitted per-tile. The bake stays
	# tractable and the resulting mesh has bounded triangle count.
	var spans: int = 0
	for ty in range(TILE_GRID_W):
		var x_start: int = -1
		for tx in range(TILE_GRID_W):
			var i: int = tx + ty * TILE_GRID_W
			var t: int = _tile_grid[i] if i < _tile_grid.size() else -1
			var is_road: bool = ROAD_TILE_INDICES.has(t)
			if is_road and x_start < 0:
				x_start = tx
			# End of span: not-road tile or end of row while in a span.
			if x_start >= 0 and (not is_road or tx == TILE_GRID_W - 1):
				var x_end_tile: int = tx + (1 if is_road else 0)
				var px_lo: float = float(x_start * TILE_GRID_PX)
				var px_hi: float = float(x_end_tile * TILE_GRID_PX)
				var py_lo: float = float(ty * TILE_GRID_PX)
				var py_hi: float = float((ty + 1) * TILE_GRID_PX)
				source.add_traversable_outline(PackedVector2Array([
					Vector2(px_lo, py_lo),
					Vector2(px_hi, py_lo),
					Vector2(px_hi, py_hi),
					Vector2(px_lo, py_hi),
				]))
				spans += 1
				x_start = -1
	for outline in building_outlines:
		source.add_obstruction_outline(outline)

	NavigationServer2D.bake_from_source_geometry_data(road_poly, source, Callable())
	road_node.navigation_polygon = road_poly
	print("[NavRoad] %d road spans baked into RoadRegion (travel_cost=%.2f)" % [spans, road_node.travel_cost])


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F2:
			Engine.time_scale = DEV_SPEED if is_equal_approx(Engine.time_scale, 1.0) else 1.0
		KEY_F3:
			# Mouse is in iso since the camera lives in iso space; project
			# back to world before injecting noise (NoiseField operates on
			# world coords like the rest of gameplay).
			NoiseBus.emit(IsoView.screen_to_world(get_global_mouse_position()), DEV_NOISE_INJECT)
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")


func _spawn_hq() -> void:
	var hq: Node2D
	match GameState.player_faction:
		GameState.Faction.TRIBAL:
			hq = TC_SCENE.instantiate()
		GameState.Faction.SURVIVOR:
			hq = SH_SCENE.instantiate()
		_:
			hq = CP_SCENE.instantiate()
	hq.position = _get_spawn_position()
	add_child(hq)
	hq.add_to_group("player_buildings")
	_player_hq = hq


func _spawn_lootables() -> void:
	# Consumes TownPlanner's lootables list (filled by Step 11). Until that
	# step is implemented, the list is empty and no Lootables spawn -
	# expected for Phase 1 of the town-gen pipeline. Hand-placed
	# NEIGHBORHOOD_LAYOUT kept as a constant for documentation but no longer
	# used to spawn from.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var lootables: Array = _town_data.get("lootables", [])
	for entry in lootables:
		var lootable = LOOTABLE_SCENE.instantiate()
		lootable.position = entry["pos"]
		lootable.neighborhood_type = entry["type"]
		var infest_rate: float = INFESTED_RATE_BY_TYPE.get(entry["type"], 0.4)
		if rng.randf() < infest_rate:
			lootable.is_infested = true
		add_child(lootable)
