extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
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
const SPAWN_NW := Vector2(576, 576)
const SPAWN_NE := Vector2(5568, 576)
const SPAWN_SW := Vector2(576, 5568)
const SPAWN_SE := Vector2(5568, 5568)

# Hand-designed neighborhood layout. To be replaced by the PZ town-layout spec
# in post-perspective-conversion work; for now sits where it was before Track 2.
const NEIGHBORHOOD_LAYOUT := [
	# NW Residential
	{ "pos": Vector2(1088, 1088), "type": "residential" },
	{ "pos": Vector2(1216, 1088), "type": "residential" },
	{ "pos": Vector2(1344, 1088), "type": "residential" },
	{ "pos": Vector2(1088, 1216), "type": "residential" },
	{ "pos": Vector2(1216, 1216), "type": "residential" },
	{ "pos": Vector2(1344, 1216), "type": "residential" },
	{ "pos": Vector2(1088, 1344), "type": "residential" },
	{ "pos": Vector2(1216, 1344), "type": "residential" },
	{ "pos": Vector2(1344, 1344), "type": "residential" },
	# NE Commercial
	{ "pos": Vector2(4384, 1088), "type": "commercial" },
	{ "pos": Vector2(4528, 1088), "type": "commercial" },
	{ "pos": Vector2(4672, 1088), "type": "commercial" },
	{ "pos": Vector2(4816, 1088), "type": "commercial" },
	{ "pos": Vector2(4960, 1088), "type": "commercial" },
	# SW Industrial
	{ "pos": Vector2(1200, 4528), "type": "industrial" },
	{ "pos": Vector2(1360, 4528), "type": "industrial" },
	{ "pos": Vector2(1200, 4688), "type": "industrial" },
	{ "pos": Vector2(1360, 4688), "type": "industrial" },
	# SE Medical/Security
	{ "pos": Vector2(4572, 4672), "type": "medical" },
	{ "pos": Vector2(4772, 4672), "type": "security" },
	# N Civic plaza
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


var _edge_timer := 0.0
var _player_hq: Node2D = null
var _opposing_hq: Node2D = null
var _match_ended: bool = false
var _win_overlay: CanvasLayer = null


func _ready() -> void:
	GameState.reset_match()
	_spawn_hq()
	_spawn_lootables()
	_rebake_navigation()
	_center_camera_on_spawn()
	if GameState.ai_enabled:
		_spawn_ai_opponent()
	else:
		_spawn_inert_opposing_hq()
	_install_win_overlay()


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
				# Mouse is in iso since the camera lives in iso space; project
				# back to world before injecting noise (NoiseField operates on
				# world coords like the rest of gameplay).
				nf.add_noise(IsoView.screen_to_world(get_global_mouse_position()), DEV_NOISE_INJECT)
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
