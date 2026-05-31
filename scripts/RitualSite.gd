class_name RitualSite
extends "res://scripts/Building.gd"

const SHAMAN_COST := 100
const SHAMAN_BUILD_TIME := 13.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var shaman_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _queue_count: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("ritual_site")


func get_action_count() -> int:
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Shaman (%d Salvage)" % SHAMAN_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(SHAMAN_COST)
	return false


func do_action(idx: int) -> void:
	if idx != 0:
		return
	if not GameState.can_spend(SHAMAN_COST):
		return
	GameState.spend(SHAMAN_COST)
	if _producing:
		_queue_count += 1
	else:
		_start_production()


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building Shaman... %.0fs" % _produce_timer
	if _queue_count > 0:
		t += "  •  Queued: %d" % _queue_count
	return t


func _start_production() -> void:
	_producing = true
	_produce_timer = SHAMAN_BUILD_TIME


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_shaman()
			_producing = false
			if _queue_count > 0:
				_queue_count -= 1
				_start_production()


const SPAWN_JITTER := 24.0


func _spawn_shaman() -> void:
	if shaman_scene == null:
		return
	var s = shaman_scene.instantiate()
	var jitter := Vector2(randf_range(-SPAWN_JITTER, SPAWN_JITTER), randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	s.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(s)


func _draw_building_icon() -> void:
	# Three small circles arranged in triangle - ritual marker
	var r := 4.0
	draw_circle(Vector2(0, -8), r, PALETTE_TRIBAL)
	draw_circle(Vector2(-8, 6), r, PALETTE_TRIBAL)
	draw_circle(Vector2(8, 6), r, PALETTE_TRIBAL)
