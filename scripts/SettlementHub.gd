class_name SettlementHub
extends "res://scripts/Building.gd"

const SCOUT_COST := 50
const ENGINEER_COST := 50
const BRAWLER_COST := 50
const SCOUT_BUILD_TIME := 8.0
const ENGINEER_BUILD_TIME := 8.0
const BRAWLER_BUILD_TIME := 8.0
const SPAWN_OFFSET := Vector2(0, 80)
const ABSOLUTE_SCOUT_CAP := 4

@export var scout_scene: PackedScene
@export var engineer_scene: PackedScene
@export var brawler_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("settlement_hub")
	add_to_group("depot")
	add_to_group("hq")


func _available_items() -> Array:
	var items = ["scout"]
	if get_tree().get_nodes_in_group("workshop").is_empty():
		items.append("engineer")
		items.append("brawler")
	return items


func get_action_count() -> int:
	return _available_items().size()


func get_action_text(idx: int) -> String:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return ""
	var item: String = items[idx]
	return "Build %s (%d Salvage)" % [item.capitalize(), _cost_for(item)]


func _cost_for(item: String) -> int:
	match item:
		"scout": return SCOUT_COST
		"engineer": return ENGINEER_COST
		"brawler": return BRAWLER_COST
		_: return 0


func get_action_available(idx: int) -> bool:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return false
	var item: String = items[idx]
	if item == "scout":
		var scout_count: int = get_tree().get_nodes_in_group("scouts").size()
		if scout_count >= _scout_cap():
			return false
	return GameState.can_spend(_cost_for(item))


func _scout_cap() -> int:
	var safehouses: int = get_tree().get_nodes_in_group("safehouse").size()
	return min(2 + 2 * safehouses, ABSOLUTE_SCOUT_CAP)


func do_action(idx: int) -> void:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return
	var item: String = items[idx]
	if item == "scout":
		var scout_count: int = get_tree().get_nodes_in_group("scouts").size()
		if scout_count >= _scout_cap():
			return
	var cost: int = _cost_for(item)
	if not GameState.can_spend(cost):
		return
	GameState.spend(cost)
	if _producing:
		_queue.append(item)
	else:
		_start_production(item)


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building %s... %.0fs" % [_produce_what.capitalize(), _produce_timer]
	if _queue.size() > 0:
		t += "  •  Queued: %d" % _queue.size()
	return t


func _start_production(item: String) -> void:
	_producing = true
	_produce_what = item
	match item:
		"scout": _produce_timer = SCOUT_BUILD_TIME
		"engineer": _produce_timer = ENGINEER_BUILD_TIME
		"brawler": _produce_timer = BRAWLER_BUILD_TIME
		_: _produce_timer = SCOUT_BUILD_TIME


func _process(delta: float) -> void:
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
	match item:
		"scout": scene = scout_scene
		"engineer": scene = engineer_scene
		"brawler": scene = brawler_scene
	if scene == null:
		return
	var u = scene.instantiate()
	var jitter := Vector2(randf_range(-SPAWN_JITTER, SPAWN_JITTER), randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	u.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(u)


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_SURVIVOR)
