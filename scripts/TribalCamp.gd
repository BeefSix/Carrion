class_name TribalCamp
extends "res://scripts/Building.gd"

const WALKER_COST := 50
const WALKER_BUILD_TIME := 20.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var walker_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _queue_count: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("tribal_camp")


func get_action_count() -> int:
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Walker (%d Salvage)" % WALKER_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(WALKER_COST)
	return false


func do_action(idx: int) -> void:
	if idx != 0:
		return
	if not GameState.can_spend(WALKER_COST):
		return
	GameState.spend(WALKER_COST)
	if _producing:
		_queue_count += 1
	else:
		_start_production()


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building Walker... %.0fs" % _produce_timer
	if _queue_count > 0:
		t += "  •  Queued: %d" % _queue_count
	return t


func _start_production() -> void:
	_producing = true
	_produce_timer = WALKER_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_walker()
			_producing = false
			if _queue_count > 0:
				_queue_count -= 1
				_start_production()


func _spawn_walker() -> void:
	if walker_scene == null:
		return
	var w = walker_scene.instantiate()
	w.position = global_position + SPAWN_OFFSET
	get_parent().add_child(w)


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_TRIBAL)
