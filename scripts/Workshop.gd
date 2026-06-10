class_name Workshop
extends "res://scripts/Building.gd"

const BRAWLER_COST := 50
const BRAWLER_BUILD_TIME := 8.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var brawler_scene: PackedScene
@export var engineer_scene: PackedScene  # populated in P3.2

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("workshop")


func get_action_count() -> int:
	# Brawler only until Engineer lands in P3.2; then 2 actions.
	if engineer_scene != null:
		return 2
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Brawler (%d Salvage)" % BRAWLER_COST
	if idx == 1 and engineer_scene != null:
		return "Build Engineer (50 Salvage)"
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(BRAWLER_COST)
	if idx == 1 and engineer_scene != null:
		return GameState.can_spend(50)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("brawler", BRAWLER_COST)
	elif idx == 1 and engineer_scene != null:
		_queue_item("engineer", 50)


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name: String = "Brawler" if _produce_what == "brawler" else "Engineer"
	var t := "Building %s... %.0fs" % [pretty_name, _produce_timer]
	if _queue.size() > 0:
		t += "  •  Queued: %d" % _queue.size()
	return t


func _queue_item(item: String, cost: int) -> void:
	if not GameState.can_spend(cost):
		return
	GameState.spend(cost)
	if _producing:
		_queue.append(item)
	else:
		_start_production(item)


func _start_production(item: String) -> void:
	_producing = true
	_produce_what = item
	_produce_timer = BRAWLER_BUILD_TIME if item == "brawler" else 8.0


func _physics_process(delta: float) -> void:
	# D5 (AUDIT 2026-06-09): production is sim state — physics tick, not wall frames.
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_item(_produce_what)
			_producing = false
			if _queue.size() > 0:
				var next_item: String = _queue.pop_front()
				_start_production(next_item)


const SPAWN_JITTER := 24.0


func _spawn_item(item: String) -> void:
	var scene: PackedScene = null
	if item == "brawler":
		scene = brawler_scene
	elif item == "engineer":
		scene = engineer_scene
	if scene == null:
		return
	var u = scene.instantiate()
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	u.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(u)


func _draw_building_icon() -> void:
	var inner_size := Vector2(40.0, 26.0)
	draw_rect(Rect2(-inner_size / 2.0, inner_size), PALETTE_SURVIVOR)
