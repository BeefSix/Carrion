extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const HQ_POSITION := Vector2(1280, 1280)
const LOOTABLE_COUNT := 30
const INFESTED_FRACTION := 0.5
const INFESTED_KEEPOUT_RADIUS := 700.0
const MAP_SIZE := Vector2(2560, 2560)
const MARGIN := 100.0
const CP_KEEPOUT_RADIUS := 250.0
const MIN_SEPARATION := 100.0
const MAX_ATTEMPTS := 2000
const DEV_SPEED := 4.0
const DEV_NOISE_INJECT := 100.0
const NEIGHBORHOOD_POOL := ["residential", "residential", "residential", "commercial", "commercial", "medical"]

const STREET_POSITIONS := [512.0, 1024.0, 1536.0, 2048.0]
const STREET_AVOID_RADIUS := 40.0


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
		_:
			hq = CP_SCENE.instantiate()
	hq.position = HQ_POSITION
	add_child(hq)


func _spawn_lootables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var cp_pos := HQ_POSITION
	var placed: Array = []
	var attempts := 0
	while placed.size() < LOOTABLE_COUNT and attempts < MAX_ATTEMPTS:
		attempts += 1
		var pos := Vector2(
			rng.randf_range(MARGIN, MAP_SIZE.x - MARGIN),
			rng.randf_range(MARGIN, MAP_SIZE.y - MARGIN)
		)
		var dist_from_cp := pos.distance_to(cp_pos)
		if dist_from_cp < CP_KEEPOUT_RADIUS:
			continue
		if _is_on_street(pos):
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_SEPARATION:
				too_close = true
				break
		if too_close:
			continue
		placed.append(pos)
		var lootable = LOOTABLE_SCENE.instantiate()
		lootable.position = pos
		lootable.neighborhood_type = NEIGHBORHOOD_POOL[rng.randi() % NEIGHBORHOOD_POOL.size()]
		if dist_from_cp >= INFESTED_KEEPOUT_RADIUS and rng.randf() < INFESTED_FRACTION:
			lootable.is_infested = true
		add_child(lootable)


func _is_on_street(pos: Vector2) -> bool:
	for sx in STREET_POSITIONS:
		if abs(pos.x - sx) < STREET_AVOID_RADIUS:
			return true
	for sy in STREET_POSITIONS:
		if abs(pos.y - sy) < STREET_AVOID_RADIUS:
			return true
	return false
