class_name Safehouse
extends "res://scripts/Building.gd"

const SCOUT_COST := 50
const SCOUT_BUILD_TIME := 25.0
const SPAWN_OFFSET := Vector2(0, 80)
const ABSOLUTE_SCOUT_CAP := 4

@export var scout_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _queue_count: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("safehouse")
	add_to_group("depot")


func get_action_count() -> int:
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Scout (%d Salvage)" % SCOUT_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx != 0:
		return false
	var scout_count: int = get_tree().get_nodes_in_group("scouts").size()
	if scout_count >= _scout_cap():
		return false
	return GameState.can_spend(SCOUT_COST)


func _scout_cap() -> int:
	var safehouses: int = get_tree().get_nodes_in_group("safehouse").size()
	return min(2 + 2 * safehouses, ABSOLUTE_SCOUT_CAP)


func do_action(idx: int) -> void:
	if idx != 0:
		return
	var scout_count: int = get_tree().get_nodes_in_group("scouts").size()
	if scout_count >= _scout_cap():
		return
	if not GameState.can_spend(SCOUT_COST):
		return
	GameState.spend(SCOUT_COST)
	if _producing:
		_queue_count += 1
	else:
		_start_production()


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building Scout... %.0fs" % _produce_timer
	if _queue_count > 0:
		t += "  •  Queued: %d" % _queue_count
	return t


func _start_production() -> void:
	_producing = true
	_produce_timer = SCOUT_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_scout()
			_producing = false
			if _queue_count > 0:
				_queue_count -= 1
				_start_production()


const SPAWN_JITTER := 24.0


func _spawn_scout() -> void:
	if scout_scene == null:
		return
	var s = scout_scene.instantiate()
	# Same jitter pattern as other unit producers - prevents stacked spawns
	# triggering physics-solver separation.
	var jitter := Vector2(randf_range(-SPAWN_JITTER, SPAWN_JITTER), randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	s.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(s)


func _draw_building_icon() -> void:
	# House icon: small triangle roof + square base
	var roof_pts := PackedVector2Array([Vector2(-12, -2), Vector2(0, -10), Vector2(12, -2)])
	draw_colored_polygon(roof_pts, PALETTE_SURVIVOR)
	draw_rect(Rect2(-10, -2, 20, 12), PALETTE_SURVIVOR)
