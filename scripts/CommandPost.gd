class_name CommandPost
extends "res://scripts/Building.gd"

const LOOTER_COST := 50
const LOOTER_BUILD_TIME := 18.0
const BARRACKS_COST := 200
const BARRACKS_BUILD_TIME := 50.0
const LOOTER_SPAWN_OFFSET := Vector2(0, 80)
const BARRACKS_SPAWN_OFFSET := Vector2(140, 0)

@export var looter_scene: PackedScene
@export var barracks_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("command_post")


func get_action_count() -> int:
	return 2


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Looter (%d Salvage)" % LOOTER_COST
	if idx == 1:
		return "Build Barracks (%d Salvage)" % BARRACKS_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(LOOTER_COST)
	if idx == 1:
		return GameState.can_spend(BARRACKS_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("looter", LOOTER_COST)
	elif idx == 1:
		_queue_item("barracks", BARRACKS_COST)


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name: String = "Looter" if _produce_what == "looter" else "Barracks"
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
	_produce_timer = LOOTER_BUILD_TIME if item == "looter" else BARRACKS_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_item(_produce_what)
			_producing = false
			if _queue.size() > 0:
				var next_item: String = _queue.pop_front()
				_start_production(next_item)


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_MILITARY)


func _spawn_item(item: String) -> void:
	if item == "looter":
		if looter_scene != null:
			var l = looter_scene.instantiate()
			l.position = global_position + LOOTER_SPAWN_OFFSET
			get_parent().add_child(l)
	elif item == "barracks":
		if barracks_scene != null:
			var b = barracks_scene.instantiate()
			b.position = global_position + BARRACKS_SPAWN_OFFSET
			get_parent().add_child(b)
			_request_nav_rebake()


func _request_nav_rebake() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")
