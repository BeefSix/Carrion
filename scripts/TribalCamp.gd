class_name TribalCamp
extends "res://scripts/Building.gd"

const WALKER_COST := 50
const WALKER_BUILD_TIME := 20.0
const HUNTING_LODGE_COST := 175
const HUNTING_LODGE_BUILD_TIME := 45.0
const WALKER_SPAWN_OFFSET := Vector2(0, 80)
const HUNTING_LODGE_SPAWN_OFFSET := Vector2(-140, 0)

@export var walker_scene: PackedScene
@export var hunting_lodge_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("tribal_camp")


func get_action_count() -> int:
	return 2


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Walker (%d Salvage)" % WALKER_COST
	if idx == 1:
		return "Build Hunting Lodge (%d Salvage)" % HUNTING_LODGE_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(WALKER_COST)
	if idx == 1:
		return GameState.can_spend(HUNTING_LODGE_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("walker", WALKER_COST)
	elif idx == 1:
		_queue_item("hunting_lodge", HUNTING_LODGE_COST)


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name: String = "Walker" if _produce_what == "walker" else "Hunting Lodge"
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
	_produce_timer = WALKER_BUILD_TIME if item == "walker" else HUNTING_LODGE_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_item(_produce_what)
			_producing = false
			if _queue.size() > 0:
				var next_item: String = _queue.pop_front()
				_start_production(next_item)


func _spawn_item(item: String) -> void:
	if item == "walker":
		if walker_scene != null:
			var w = walker_scene.instantiate()
			w.position = global_position + WALKER_SPAWN_OFFSET
			get_parent().add_child(w)
	elif item == "hunting_lodge":
		if hunting_lodge_scene != null:
			var hl = hunting_lodge_scene.instantiate()
			hl.position = global_position + HUNTING_LODGE_SPAWN_OFFSET
			get_parent().add_child(hl)


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_TRIBAL)
