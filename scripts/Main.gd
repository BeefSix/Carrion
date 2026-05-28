extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const SH_SCENE := preload("res://scenes/buildings/SettlementHub.tscn")
const DECORATION_SCENE := preload("res://scenes/buildings/Decoration.tscn")
const PROP_SCENE := preload("res://scenes/Prop.tscn")

# Duplicated from Decoration.PALETTES because GDScript's headless parse can't
# resolve cross-script class consts before class_name globals are indexed
# (see project memory: "class_name cold-load resolution error"). Keep in sync
# with scripts/Decoration.gd if either side changes.
const DECORATION_PALETTES := {
	"residential": [Color("8e6e4a"), Color("a07840"), Color("7a5e3a"), Color("946a38")],
	"commercial": [Color("c47a4b"), Color("5a8a85"), Color("a45040"), Color("8a7a3f")],
	"industrial": [Color("4a4540"), Color("5a4030"), Color("3a352e"), Color("4e4842")],
	"medical": [Color("9aaaaa"), Color("8aa0a8"), Color("aab6b8"), Color("9ca6a4")],
	"security": [Color("3a4a68"), Color("2e3a55"), Color("46587a"), Color("3a3e58")],
	"civic": [Color("a4a08e"), Color("7a8270"), Color("c0bba2"), Color("8e8a78")],
}
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
# Each corner sits closest to a different neighborhood so the three factions experience
# a different first-encounter when they leave their spawn:
#   Military NW -> Residential cluster
#   Tribal  SE -> Medical / Security institutional pair
#   Survivor SW -> Industrial warehouse complex
const SPAWN_NW := Vector2(576, 576)
const SPAWN_NE := Vector2(5568, 576)
const SPAWN_SW := Vector2(576, 5568)
const SPAWN_SE := Vector2(5568, 5568)

# Hand-designed neighborhood layout. Each district packs its buildings tightly
# (close center-to-center spacing within the district); districts sit in the
# four quadrants + north-center civic, with open corridors between them and
# the HQ in the middle.
const NEIGHBORHOOD_LAYOUT := [
	# NW Residential — 3x3 grid of small 2x2 houses, tight 128 px spacing
	{ "pos": Vector2(1088, 1088), "type": "residential" },
	{ "pos": Vector2(1216, 1088), "type": "residential" },
	{ "pos": Vector2(1344, 1088), "type": "residential" },
	{ "pos": Vector2(1088, 1216), "type": "residential" },
	{ "pos": Vector2(1216, 1216), "type": "residential" },
	{ "pos": Vector2(1344, 1216), "type": "residential" },
	{ "pos": Vector2(1088, 1344), "type": "residential" },
	{ "pos": Vector2(1216, 1344), "type": "residential" },
	{ "pos": Vector2(1344, 1344), "type": "residential" },

	# NE Commercial — strip of 5 wide 3x2 buildings along a main street
	{ "pos": Vector2(4384, 1088), "type": "commercial" },
	{ "pos": Vector2(4528, 1088), "type": "commercial" },
	{ "pos": Vector2(4672, 1088), "type": "commercial" },
	{ "pos": Vector2(4816, 1088), "type": "commercial" },
	{ "pos": Vector2(4960, 1088), "type": "commercial" },

	# SW Industrial — 2x2 grid of 3x3 warehouses, wider 160 px spacing
	{ "pos": Vector2(1200, 4528), "type": "industrial" },
	{ "pos": Vector2(1360, 4528), "type": "industrial" },
	{ "pos": Vector2(1200, 4688), "type": "industrial" },
	{ "pos": Vector2(1360, 4688), "type": "industrial" },

	# SE Medical/Security — 2 institutional 3x3 buildings
	{ "pos": Vector2(4572, 4672), "type": "medical" },
	{ "pos": Vector2(4772, 4672), "type": "security" },

	# N Civic plaza — 2 institutional 3x3 buildings north of the HQ
	{ "pos": Vector2(2952, 896), "type": "civic" },
	{ "pos": Vector2(3192, 896), "type": "civic" },
]

const INFESTED_RATE_BY_TYPE := {
	"residential": 0.4,
	"commercial": 0.3,
	"industrial": 0.5,
	"medical": 1.0,
	"security": 1.0,
	"civic": 0.5,
}

# Decoration fill regions (tile coordinates within the 192x192 grid). Decorations
# spawn procedurally inside each region, avoiding road/sidewalk bands (the
# regions already sit between the roads at x=65, x=126, y=65, y=126) and
# avoiding the hand-placed Lootables. Each district uses a mix of two footprint
# sizes for visual variety inside the cohesive palette.
const DECORATION_REGIONS := [
	{
		"region": Rect2(10, 10, 53, 53), "type": "residential",
		"target_count": 26, "footprints": [Vector2(64, 64), Vector2(32, 32)],
	},
	{
		"region": Rect2(128, 10, 54, 53), "type": "commercial",
		"target_count": 18, "footprints": [Vector2(96, 64), Vector2(64, 64)],
	},
	{
		"region": Rect2(10, 128, 53, 54), "type": "industrial",
		"target_count": 14, "footprints": [Vector2(96, 96), Vector2(64, 96)],
	},
	{
		"region": Rect2(128, 128, 54, 54), "type": "medical",
		"target_count": 12, "footprints": [Vector2(96, 96), Vector2(64, 64)],
	},
	{
		"region": Rect2(68, 10, 55, 53), "type": "civic",
		"target_count": 16, "footprints": [Vector2(96, 96), Vector2(64, 64)],
	},
]

const PLACEMENT_ATTEMPTS_PER_TARGET := 8
const SPAWN_KEEPOUT_PX := 384.0

# Road centerlines mirrored from GroundTiles.ROAD_LANES_*. Used by prop placement
# so cars and dumpsters sit on sidewalks adjacent to actual streets.
const ROAD_LANES_X := [65, 126]
const ROAD_LANES_Y := [65, 126]
const ROAD_HALF_WIDTH := 1
const SIDEWALK_BAND := 2
const TILE_PX := 32
const PROPS_PER_ROAD := 30
const CAR_COLORS := [
	Color("2a2a2a"), Color("3a2a25"), Color("2e2e3a"),
	Color("443028"), Color("38333a"), Color("3a3a2c"),
]
const DUMPSTER_COLORS := [Color("3a4838"), Color("3a3a3a"), Color("452820")]
const RUBBLE_COLOR := Color("4a4540")
const PLANTER_COLOR := Color("5a3e2a")


var _edge_timer := 0.0
var _player_hq: Node2D = null
var _opposing_hq: Node2D = null
var _match_ended: bool = false
var _win_overlay: CanvasLayer = null


func _ready() -> void:
	GameState.reset_match()
	_spawn_hq()
	_spawn_lootables()
	_spawn_decorations()
	_spawn_props()
	_rebake_navigation()
	_center_camera_on_spawn()
	if GameState.ai_enabled:
		_spawn_ai_opponent()
	else:
		_spawn_inert_opposing_hq()
	_install_win_overlay()


func _spawn_props() -> void:
	# Cars and dumpsters lined along roads; rubble piles around the rubble edge
	# band. Deterministic seed; placement avoids HQ keepouts so props don't
	# crowd starting positions.
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	# Cars along E-W roads
	for lane_y in ROAD_LANES_Y:
		_spawn_road_props(rng, lane_y, true)
	# Cars along N-S roads
	for lane_x in ROAD_LANES_X:
		_spawn_road_props(rng, lane_x, false)
	# Rubble piles around the inner rim
	_spawn_rubble_ring(rng)


func _spawn_road_props(rng: RandomNumberGenerator, lane: int, horizontal: bool) -> void:
	# Walk the road, every ~150 px try a prop (mostly car, occasional dumpster).
	# Place on the sidewalk band (2 tiles either side of the road body).
	const STEP_PX := 150.0
	const MAP_SIZE_PX := 6144.0
	const SIDEWALK_DIST_PX := float((ROAD_HALF_WIDTH + 1) * TILE_PX)
	var along: float = 320.0
	while along < MAP_SIZE_PX - 320.0:
		along += STEP_PX + rng.randf_range(-40.0, 40.0)
		var side: int = -1 if rng.randf() < 0.5 else 1
		var lane_px: float = float(lane) * TILE_PX + TILE_PX * 0.5
		var pos: Vector2
		if horizontal:
			pos = Vector2(along, lane_px + side * SIDEWALK_DIST_PX)
		else:
			pos = Vector2(lane_px + side * SIDEWALK_DIST_PX, along)
		if _spawn_keepout(pos):
			continue
		if _building_collides(pos, Vector2(40, 40)):
			continue
		var roll: float = rng.randf()
		var prop = PROP_SCENE.instantiate()
		prop.position = pos
		if roll < 0.78:
			prop.set("kind", 0)  # CAR
			prop.set("body_color", CAR_COLORS[rng.randi() % CAR_COLORS.size()])
			prop.set("orientation", 0 if horizontal else 1)
		else:
			prop.set("kind", 1)  # DUMPSTER
			prop.set("body_color", DUMPSTER_COLORS[rng.randi() % DUMPSTER_COLORS.size()])
		add_child(prop)


func _spawn_rubble_ring(rng: RandomNumberGenerator) -> void:
	# Scatter rubble piles around the inner perimeter (just inside the rubble
	# tile edge band). Visual signal of the city's outer decay.
	const INNER := 256.0
	const OUTER := 480.0
	for i in range(80):
		var edge: int = i % 4
		var t: float = rng.randf()
		var dist: float = rng.randf_range(INNER, OUTER)
		var pos: Vector2
		match edge:
			0: pos = Vector2(t * 6144.0, dist)
			1: pos = Vector2(6144.0 - dist, t * 6144.0)
			2: pos = Vector2(t * 6144.0, 6144.0 - dist)
			_: pos = Vector2(dist, t * 6144.0)
		if _spawn_keepout(pos):
			continue
		if _building_collides(pos, Vector2(24, 24)):
			continue
		var prop = PROP_SCENE.instantiate()
		prop.position = pos
		prop.set("kind", 3)  # RUBBLE_PILE
		prop.set("body_color", RUBBLE_COLOR)
		add_child(prop)


func _spawn_decorations() -> void:
	# Procedural fill within each district region. Snap to a 32-px grid (tile
	# resolution) so decorations align cleanly with the ground. Reject placements
	# that collide with any existing building (Lootables already spawned) or fall
	# inside a spawn-corner keepout (so HQs and starting units have breathing
	# room). Each district pulls colors from Decoration.PALETTES.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for entry in DECORATION_REGIONS:
		var region: Rect2 = entry["region"]
		var district_type: String = entry["type"]
		var target: int = entry["target_count"]
		var footprints: Array = entry["footprints"]
		var palette: Array = DECORATION_PALETTES.get(district_type, [Color("5a4530")])
		var attempts: int = target * PLACEMENT_ATTEMPTS_PER_TARGET
		var placed: int = 0
		while placed < target and attempts > 0:
			attempts -= 1
			var footprint: Vector2 = footprints[rng.randi() % footprints.size()]
			var tw: int = int(footprint.x / 32.0)
			var th: int = int(footprint.y / 32.0)
			var max_x: int = int(region.size.x) - tw - 1
			var max_y: int = int(region.size.y) - th - 1
			if max_x <= 1 or max_y <= 1:
				continue
			var tx: int = int(region.position.x) + rng.randi_range(1, max_x)
			var ty: int = int(region.position.y) + rng.randi_range(1, max_y)
			var pos := Vector2(
				float(tx * 32) + footprint.x * 0.5,
				float(ty * 32) + footprint.y * 0.5,
			)
			if _spawn_keepout(pos):
				continue
			if _building_collides(pos, footprint):
				continue
			var deco = DECORATION_SCENE.instantiate()
			deco.position = pos
			# set() rather than direct property assignment - sidesteps the cold-
			# load typed-export check that fires in headless before class globals
			# are indexed.
			deco.set("district_type", district_type)
			deco.set("size_pixels", footprint)
			deco.set("body_color", palette[rng.randi() % palette.size()])
			add_child(deco)
			placed += 1


func _spawn_keepout(pos: Vector2) -> bool:
	# Reject if too close to any potential player/AI spawn corner.
	for spawn in [SPAWN_NW, SPAWN_NE, SPAWN_SW, SPAWN_SE]:
		if pos.distance_to(spawn) < SPAWN_KEEPOUT_PX:
			return true
	return false


func _building_collides(pos: Vector2, footprint: Vector2) -> bool:
	# Padded AABB intersection against every building already in the tree. Pad
	# by 16 px so adjacent buildings still leave a 1-tile gap for unit movement.
	var pad := Vector2(16, 16)
	var rect := Rect2(pos - footprint * 0.5 - pad, footprint + pad * 2.0)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if not ("size_pixels" in b):
			continue
		var bhalf: Vector2 = b.size_pixels * 0.5
		var brect := Rect2(b.position - bhalf, b.size_pixels)
		if rect.intersects(brect):
			return true
	return false


func _spawn_ai_opponent() -> void:
	# Phase 1: AI is always Military, spawns at the corner opposite the player.
	var ai_scene := load("res://scripts/ai/AIController.gd") as Script
	if ai_scene == null:
		return
	var ai = ai_scene.new()
	ai.faction = GameState.Faction.MILITARY
	ai.spawn_position = _get_ai_spawn_position()
	ai.enemy_hq_position = _get_spawn_position()
	add_child(ai)


func _spawn_inert_opposing_hq() -> void:
	# Week 4 inert opposing faction - HQ exists at the opposite corner, no units,
	# does nothing. Lets the player walk over and "win" the match. Faction picked
	# to be different from the player's so the win condition is meaningful.
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
	# Called by AIController after it spawns its CP so Main can monitor it.
	_opposing_hq = hq


func _install_win_overlay() -> void:
	_win_overlay = WIN_OVERLAY_SCENE.instantiate()
	add_child(_win_overlay)


func _check_win_conditions() -> void:
	if _match_ended:
		return
	# Player HQ gone -> defeat. Opposing HQ gone -> victory. We resolve via
	# is_instance_valid because queue_free has already fired by the time we get
	# here in the frame after destroyed.emit.
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
	# Mirror across the map - AI takes the corner opposite the player's.
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
	if has_node("Camera"):
		$Camera.position = _get_spawn_position()


func rebake_navigation() -> void:
	# Public re-bake hook so runtime-built buildings can request a refresh.
	_rebake_navigation()


func _rebake_navigation() -> void:
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

	var pad := 4.0
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_in_group("walls"):
			continue
		if not ("size_pixels" in b):
			continue
		var half: Vector2 = b.size_pixels * 0.5
		var p: Vector2 = b.position
		source.add_obstruction_outline(PackedVector2Array([
			p + Vector2(-half.x - pad, -half.y - pad),
			p + Vector2(half.x + pad, -half.y - pad),
			p + Vector2(half.x + pad, half.y + pad),
			p + Vector2(-half.x - pad, half.y + pad),
		]))

	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source, Callable())
	$NavRegion.navigation_polygon = nav_poly


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F2:
			Engine.time_scale = DEV_SPEED if is_equal_approx(Engine.time_scale, 1.0) else 1.0
		KEY_F3:
			var nf := get_tree().get_first_node_in_group("noise_field")
			if nf != null:
				nf.add_noise(get_global_mouse_position(), DEV_NOISE_INJECT)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for entry in NEIGHBORHOOD_LAYOUT:
		var lootable = LOOTABLE_SCENE.instantiate()
		lootable.position = entry["pos"]
		lootable.neighborhood_type = entry["type"]
		var infest_rate: float = INFESTED_RATE_BY_TYPE.get(entry["type"], 0.4)
		if rng.randf() < infest_rate:
			lootable.is_infested = true
		add_child(lootable)
