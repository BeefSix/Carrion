extends Node2D

const LOOTABLE_SCENE := preload("res://scenes/buildings/Lootable.tscn")
const LOOTABLE_COUNT := 30
const MAP_SIZE := Vector2(2560, 2560)
const MARGIN := 100.0
const CP_KEEPOUT_RADIUS := 250.0
const MIN_SEPARATION := 100.0
const MAX_ATTEMPTS := 2000


func _ready() -> void:
	_spawn_lootables()


func _spawn_lootables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var cp_pos := Vector2(1280, 1280)
	var placed: Array = []
	var attempts := 0
	while placed.size() < LOOTABLE_COUNT and attempts < MAX_ATTEMPTS:
		attempts += 1
		var pos := Vector2(
			rng.randf_range(MARGIN, MAP_SIZE.x - MARGIN),
			rng.randf_range(MARGIN, MAP_SIZE.y - MARGIN)
		)
		if pos.distance_to(cp_pos) < CP_KEEPOUT_RADIUS:
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
		add_child(lootable)
