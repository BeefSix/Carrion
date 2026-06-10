extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const TOWN_PLANNER_SCRIPT := preload("res://scripts/maps/TownPlanner.gd")
const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const SH_SCENE := preload("res://scenes/buildings/SettlementHub.tscn")
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const NoiseFieldScript := preload("res://scripts/NoiseField.gd")
const WIN_OVERLAY_SCENE := preload("res://scenes/WinOverlay.tscn")
const MAP_SIZE := WorldConstants.MAP_SIZE  # single source: WorldConstants
const DEV_SPEED := 4.0
const DEV_NOISE_INJECT := 100.0

# Edge wanderer: low-rate ambient zombie drift in from off-map.
const EDGE_SPAWN_INTERVAL := 90.0
const EDGE_INSET := 60.0
const EDGE_SPAWN_KEEPOUT := 1200.0  # avoid dumping wanderers on top of the player corner
# Ambient zombie variant mix for edge wanderers (§3.3). See _spawn_edge_wanderer.
const EDGE_BRUTE_CHANCE := 0.06
const EDGE_RUNNER_CHANCE := 0.04

# AI-vs-AI hard cap on match duration (sim seconds). If neither HQ falls by
# then we force a "timeout" result so headless batches don't hang forever.
# 600s gives ~10 sim min - enough for the strategist's ATTACK phase to enter
# (units cross ATTACK_THRESHOLD at sim ~200s) and dispatch the rally pool at
# least once. Late-game CPU saturation (471+ units) drags effective time_scale
# to ~1x, so a longer cap turns sweep budgets into multi-hour runs.
const AI_VS_AI_MAX_DURATION_SIM_SEC := 600.0

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


func _ready() -> void:
	# Global color grade ("skin the maps" pass, 2026-06-11): one subtle
	# CanvasModulate glues tiles, buildings, units, and props into a single
	# bleak register — the cheapest "looks like one game" lever there is.
	# World canvas only; the HUD lives on its own CanvasLayer, unaffected.
	# RENDER-ONLY.
	var grade := CanvasModulate.new()
	grade.color = Color(0.93, 0.92, 0.89)
	add_child(grade)
	# --replay=<path> overrides everything: load recorded JSONL, seed SimRng
	# from the header, apply the recorded town snapshot. Done BEFORE
	# reset_match so the override seed survives, and BEFORE map planning so
	# the snapshot replaces the live TownPlanner pass.
	var user_args := OS.get_cmdline_user_args()
	var replay_path: String = ""
	for arg in user_args:
		if arg.begins_with("--replay="):
			replay_path = arg.substr("--replay=".length())
			break
	if replay_path != "":
		if not ReplayRecorder.load_replay(replay_path):
			push_warning("Replay load failed; falling back to normal startup.")
		else:
			# Inject recorded seed before reset_match so its randi() override
			# path takes the recorded value.
			OS.set_environment("CARRION_REPLAY_SEED", str(ReplayRecorder.playback_seed()))
	GameState.reset_match()
	if replay_path != "" and ReplayRecorder.is_playing:
		# Force the recorded seed (reset_match honors the env override).
		GameState.match_seed = ReplayRecorder.playback_seed()
		SimRng.seed_with(GameState.match_seed)
	# Image-to-map PoC: when GameState.custom_map_path is set, load that JSON
	# instead of running TownPlanner. The image is rendered as an iso-projected
	# Polygon2D background covering the world's diamond view space.
	# Authored map recipes (MAP_DESIGN.md): --map=downtown|terrace|orchard
	# or the title-screen picker. Deterministic authored layouts producing
	# the same town-data contract TownPlanner does.
	for arg in user_args:
		if arg.begins_with("--map="):
			GameState.map_recipe = arg.get_slice("=", 1)
	if ReplayRecorder.is_playing:
		# Replay: rebuild town from the recorded snapshot so playback
		# doesn't depend on TownPlanner being deterministic across runs.
		_apply_replay_town(ReplayRecorder.playback_town())
	elif GameState.map_recipe != "":
		_town_data = preload("res://scripts/maps/MapRecipes.gd").build(GameState.map_recipe)
		if _town_data.is_empty():
			push_warning("Unknown map recipe '%s' — falling back to procgen" % GameState.map_recipe)
			var planner_fb = TOWN_PLANNER_SCRIPT.new()
			_town_data = planner_fb.plan_town()
		$GroundTiles.apply_tile_grid(_town_data["tile_grid"])
		_spawn_scenery()
	elif GameState.custom_map_path != "":
		_load_custom_map(GameState.custom_map_path)
	else:
		# Standard procedural town generation. TownPlanner runs its 12-step
		# pipeline and hands back tile_grid + lots + buildings + lootables.
		var planner = TOWN_PLANNER_SCRIPT.new()
		_town_data = planner.plan_town()
		$GroundTiles.apply_tile_grid(_town_data["tile_grid"])
	if GameState.ai_vs_ai_mode:
		# AI-vs-AI replaces the normal player_hq + opposing_hq spawn flow with
		# two AIControllers: one in the player slot (tags player_units /
		# player_buildings, sets _player_hq), one in the AI slot (existing
		# behavior). Lootables, nav, MatchStats all work unchanged.
		# Speed up sim so the 1800s sim-time safety cap doesn't take 30 min
		# wall time when nothing decisive happens. 8x makes a stalemated match
		# fit in ~3.75 min wall and a 30-match sweep run in ~2 hr worst case.
		# Headless has no rendering so the higher tick rate is CPU-only.
		Engine.time_scale = DEV_SPEED * 2.0
		_spawn_ai_vs_ai_opponents()
	else:
		_spawn_hq()
	_spawn_lootables()
	_rebake_navigation()
	_center_camera_on_spawn()
	if not GameState.ai_vs_ai_mode:
		if GameState.ai_enabled:
			_spawn_ai_opponent()
		else:
			_spawn_inert_opposing_hq()
	_install_win_overlay()
	# Telemetry header: built once all match-shape state (matchup, ai_enabled,
	# map source) is locked in. MatchStats owns the schema; we just trigger it.
	MatchStats.match_start()
	# Replay recording: starts AFTER MatchStats but BEFORE any sim-tick-zero
	# commands could be issued. Town snapshot is captured into the replay
	# header so playback doesn't depend on TownPlanner being deterministic.
	ReplayRecorder.start_recording(_town_data)
	# Diagnostic hook (2026-06-08): --repro-hg-horde drops 1 HG + 2 Riflemen
	# next to the player HQ, then a 150-Shambler cluster ~800 px ahead, and
	# issues a move order at the horde center. Reproduces the player's
	# "near-total system hang on group move into horde" report headlessly so
	# the actual symptom can be measured. Remove after the bug is fixed.
	if "--repro-hg-horde" in user_args:
		_repro_hg_horde()


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
		$GroundTiles.apply_tile_grid(_town_data["tile_grid"])
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


func _spawn_ai_vs_ai_opponents() -> void:
	# Headless balance-lab path. Two AIControllers, mirrored: one drives the
	# player slot (player spawn position, player_* ownership tags), the other
	# drives the opposing slot (AI spawn position, ai_* tags). Default
	# matchup is Military mirror.
	var ai_script := load("res://scripts/ai/AIController.gd") as Script
	if ai_script == null:
		return
	var player_pos: Vector2 = _get_spawn_position()
	var ai_pos: Vector2 = _get_ai_spawn_position()
	# A4: --matchup=XY picks the factions (X = player slot, Y = opposing;
	# M = Military, T = Tribal). Default MM preserves the existing mirror.
	var matchup: String = "MM"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matchup="):
			matchup = arg.get_slice("=", 1).to_upper()
	var player_ai = ai_script.new()
	player_ai.faction = GameState.Faction.TRIBAL if matchup.substr(0, 1) == "T" else GameState.Faction.MILITARY
	player_ai.spawn_position = player_pos
	player_ai.enemy_hq_position = ai_pos
	player_ai.as_player_slot = true
	add_child(player_ai)
	var opposing_ai = ai_script.new()
	opposing_ai.faction = GameState.Faction.TRIBAL if matchup.substr(1, 1) == "T" else GameState.Faction.MILITARY
	opposing_ai.spawn_position = ai_pos
	opposing_ai.enemy_hq_position = player_pos
	opposing_ai.as_player_slot = false
	add_child(opposing_ai)


func _repro_hg_horde() -> void:
	# Direct repro of "player issues group move into horde -> hang".
	# Spawns 1 HG + 2 Riflemen as player_units / MILITARY, drops a 150-zombie
	# ring 800 px ahead, then calls move_to(horde_center) on the trio so the
	# scenario fires the moment the engine starts the first physics frame.
	# No AI involvement; the only sim load comes from the unit interactions.
	var origin: Vector2 = _get_spawn_position()
	var horde_center: Vector2 = origin + Vector2(800.0, 0.0)
	var rifleman_scene: PackedScene = load("res://scenes/units/Rifleman.tscn")
	var heavy_scene: PackedScene = load("res://scenes/units/HeavyGunner.tscn")
	if rifleman_scene == null or heavy_scene == null:
		print("[REPRO] missing unit scenes - abort")
		return
	var hg = heavy_scene.instantiate()
	hg.position = origin
	hg.faction = GameState.Faction.MILITARY
	add_child(hg)
	hg.add_to_group("player_units")
	for i in range(2):
		var r = rifleman_scene.instantiate()
		r.position = origin + Vector2(32.0 * float(i + 1), 32.0)
		r.faction = GameState.Faction.MILITARY
		add_child(r)
		r.add_to_group("player_units")
	# Horde: 150 Shamblers in an annular cluster around horde_center.
	for i in range(150):
		var ang: float = (float(i) / 150.0) * TAU
		var radius: float = 80.0 + float(i % 12) * 10.0
		var s = SHAMBLER_SCENE.instantiate()
		s.position = horde_center + Vector2(cos(ang), sin(ang)) * radius
		add_child(s)
	# Group move command (matches what SelectionManager._handle_right_click
	# would issue on a real player click - move_to per unit).
	for u in get_tree().get_nodes_in_group("player_units"):
		if u.has_method("move_to"):
			u.move_to(horde_center)
	print("[REPRO] spawned 1 HG + 2 Riflemen at %s, 150 Shamblers around %s, move issued" % [origin, horde_center])


func _apply_replay_town(town: Dictionary) -> void:
	# Rehydrate the town from the recorded snapshot: tile_grid bytes back into
	# a PackedByteArray, lootables list back into the dict shape that
	# _spawn_lootables consumes.
	var grid := PackedByteArray()
	var grid_arr: Array = town.get("tile_grid", [])
	grid.resize(grid_arr.size())
	for i in range(grid_arr.size()):
		grid[i] = int(grid_arr[i])
	$GroundTiles.apply_tile_grid(grid)
	var lootables: Array = []
	for entry in town.get("lootables", []):
		var pos_arr = entry.get("pos", [0, 0])
		lootables.append({
			"pos": Vector2(pos_arr[0], pos_arr[1]),
			"type": entry.get("type", "residential"),
		})
	_town_data = {"lootables": lootables}


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


func set_player_hq(hq: Node2D) -> void:
	# AI-vs-AI: the "player slot" AIController calls this from its _spawn_hq
	# so Main's win-condition tracks the correct node. Mirrors set_opposing_hq.
	_player_hq = hq


func _install_win_overlay() -> void:
	_win_overlay = WIN_OVERLAY_SCENE.instantiate()
	add_child(_win_overlay)


func _check_win_conditions() -> void:
	if _match_ended:
		return
	# AI-vs-AI: hard timeout so a stalemate doesn't hang headless batches.
	if GameState.ai_vs_ai_mode and GameState.sim_seconds() >= AI_VS_AI_MAX_DURATION_SIM_SEC:
		_finalize_match("timeout", "NONE")
		return
	if _player_hq != null and not is_instance_valid(_player_hq):
		_finalize_match("defeat", "AI" if GameState.ai_enabled else "NONE")
		if _win_overlay != null:
			_win_overlay.show_defeat()
		return
	if _opposing_hq != null and not is_instance_valid(_opposing_hq):
		_finalize_match("victory", "PLAYER")
		if _win_overlay != null:
			_win_overlay.show_victory()


func _finalize_match(result: String, winner_faction: String) -> void:
	_match_ended = true
	MatchStats.match_end({
		"result": result,
		"winner_faction": winner_faction,
		"duration_sim_sec": GameState.sim_seconds(),
	})
	ReplayRecorder.stop_recording({
		"result": result,
		"winner_faction": winner_faction,
	})
	GameState.end_match()
	# AI-vs-AI is a headless batch run; quit the process so the calling script
	# (CI, balance lab) sees an exit code and can move on to the next seed.
	# Deferred so MatchStats's close-on-end and any in-flight queue_redraw
	# settle before SceneTree teardown.
	if GameState.ai_vs_ai_mode:
		get_tree().quit.call_deferred()


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
	# Population cap (2026-06-08): edge wanderers are ambient atmospheric
	# spawns and should respect the same MAX_ZOMBIE_POPULATION ceiling
	# that horde spawns and corpse rises now enforce. Without this gate,
	# the every-90-seconds drip would still push past the cap in long
	# matches once the other sites were locked down.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombie_count"):
		if zf.get_zombie_count() >= NoiseFieldScript.MAX_ZOMBIE_POPULATION:
			return
	var spawn_pos := _get_spawn_position()
	var pos := Vector2.ZERO
	for attempt in range(8):
		var edge: int = SimRng.randi() % 4
		match edge:
			0:
				pos = Vector2(SimRng.randf_range(EDGE_INSET, MAP_SIZE.x - EDGE_INSET), EDGE_INSET)
			1:
				pos = Vector2(MAP_SIZE.x - EDGE_INSET, SimRng.randf_range(EDGE_INSET, MAP_SIZE.y - EDGE_INSET))
			2:
				pos = Vector2(SimRng.randf_range(EDGE_INSET, MAP_SIZE.x - EDGE_INSET), MAP_SIZE.y - EDGE_INSET)
			_:
				pos = Vector2(EDGE_INSET, SimRng.randf_range(EDGE_INSET, MAP_SIZE.y - EDGE_INSET))
		if pos.distance_to(spawn_pos) >= EDGE_SPAWN_KEEPOUT:
			break
	var s = SHAMBLER_SCENE.instantiate()
	# Ambient variant texture (§3.3). Brutes lean toward the edge-wanderer
	# path because their identity is the far-wandering horde-nucleus that
	# drags a cluster across the map; Runners stay rarer ambiently than in
	# hordes (a surprise Runner with no warning is unfair pressure).
	var roll: float = SimRng.randf()
	if roll < EDGE_BRUTE_CHANCE:
		s.set_variant(s.VARIANT_BRUTE)
	elif roll < EDGE_BRUTE_CHANCE + EDGE_RUNNER_CHANCE:
		s.set_variant(s.VARIANT_RUNNER)
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
	# Dedup-union the obstruction set from "buildings" and "lootable". Lootables
	# extend Building and inherit the "buildings" tag, but the feel-test caught
	# units walking through houses regardless - explicit inclusion via the
	# "lootable" group is the belt-and-suspenders fix (and protects against
	# any future Lootable that skips Building._ready). Dictionary by instance
	# id gives deterministic insertion-order iteration without double-baking.
	var obstacles: Dictionary = {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if b == null or not is_instance_valid(b) or b.is_in_group("walls"):
			continue
		obstacles[b.get_instance_id()] = b
	for l in get_tree().get_nodes_in_group("lootable"):
		if l == null or not is_instance_valid(l):
			continue
		obstacles[l.get_instance_id()] = l
	for b in obstacles.values():
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
		# Authored recipes decide infestation explicitly (the R/L/I mix IS
		# the map design); procgen entries keep the per-type rate roll.
		if entry.has("infested"):
			lootable.is_infested = bool(entry["infested"])
		else:
			var infest_rate: float = INFESTED_RATE_BY_TYPE.get(entry["type"], 0.4)
			if rng.randf() < infest_rate:
				lootable.is_infested = true
		add_child(lootable)


const SCENERY_SCENE := preload("res://scenes/buildings/SceneryBuilding.tscn")
const PROP_SCRIPT := preload("res://scripts/Prop.gd")
# Doodad textures (assets/props, generated 2026-06-09). Render-only —
# see Prop.gd. Keys match MapRecipes.PROP_TABLES kinds.
const PROP_TEXTURES := {
	"car": preload("res://assets/props/abandoned_car.png"),
	"tree": preload("res://assets/props/dead_tree.png"),
	"dumpster": preload("res://assets/props/dumpster.png"),
	"barrel": preload("res://assets/props/oil_barrel.png"),
	"cart": preload("res://assets/props/shopping_cart.png"),
	"lamp": preload("res://assets/props/lamp_post.png"),
	"bench": preload("res://assets/props/park_bench.png"),
	"cone": preload("res://assets/props/traffic_cone.png"),
	"hydrant": preload("res://assets/props/fire_hydrant.png"),
	"mailbox": preload("res://assets/props/mailbox.png"),
	"pallet": preload("res://assets/props/wood_pallet.png"),
	"brickpile": preload("res://assets/props/brick_pile.png"),
}


func _spawn_scenery() -> void:
	# Regular buildings (MAP_DESIGN.md): collision + occlusion, no use.
	for entry in _town_data.get("scenery", []):
		var b = SCENERY_SCENE.instantiate()
		b.position = entry["pos"]
		b.neighborhood_type = entry["type"]
		add_child(b)
	_spawn_props()


func _spawn_props() -> void:
	# Render-only doodads from the recipe's deterministic scatter.
	for entry in _town_data.get("props", []):
		var tex: Texture2D = PROP_TEXTURES.get(entry["kind"])
		if tex == null:
			continue
		var prop := Node2D.new()
		prop.set_script(PROP_SCRIPT)
		prop.position = entry["pos"]
		prop.texture = tex
		add_child(prop)
	# Ground wear decals (TerrainKit Phase 3): one render-only node draws
	# every stain/crack/litter splat between the tiles and the units.
	var decal_entries: Array = _town_data.get("decals", [])
	if decal_entries.size() > 0:
		var decals := Node2D.new()
		decals.name = "GroundDecals"
		decals.set_script(preload("res://scripts/GroundDecals.gd"))
		add_child(decals)
		decals.set_decals(decal_entries)
