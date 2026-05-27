class_name CommandPost
extends "res://scripts/Building.gd"

const LOOTER_COST := 50
const LOOTER_BUILD_TIME := 18.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var looter_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("command_post")


func primary_action() -> void:
	if not GameState.can_spend(LOOTER_COST):
		return
	GameState.spend(LOOTER_COST)
	if _producing:
		_queue.append("looter")
	else:
		_start_production("looter")


func has_action() -> bool:
	return true


func get_action_button_text() -> String:
	return "Build Looter (%d Salvage)" % LOOTER_COST


func get_action_available() -> bool:
	return GameState.can_spend(LOOTER_COST)


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building Looter... %.0fs" % _produce_timer
	if _queue.size() > 0:
		t += "  •  Queued: %d" % _queue.size()
	return t


func _start_production(_item: String) -> void:
	_producing = true
	_produce_timer = LOOTER_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_looter()
			_producing = false
			if _queue.size() > 0:
				var next_item: String = _queue.pop_front()
				_start_production(next_item)


func _spawn_looter() -> void:
	if looter_scene == null:
		return
	var looter = looter_scene.instantiate()
	looter.position = global_position + SPAWN_OFFSET
	get_parent().add_child(looter)
