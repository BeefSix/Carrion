extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const SH_SCENE := preload("res://scenes/buildings/SettlementHub.tscn")
const HQ_POSITION := Vector2(3072, 3072)
const MAP_SIZE := Vector2(6144, 6144)
const DEV_SPEED := 4.0
const DEV_NOISE_INJECT := 100.0

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


func _ready() -> void:
	GameState.reset_match()
	_spawn_hq()
	_spawn_lootables()


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
	hq.position = HQ_POSITION
	add_child(hq)


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
