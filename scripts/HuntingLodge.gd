class_name HuntingLodge
extends "res://scripts/Building.gd"

const HUNTER_COST := 50
const HUNTER_BUILD_TIME := 10.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var hunter_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _queue_count: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("hunting_lodge")


func get_action_count() -> int:
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Hunter (%d Salvage)" % HUNTER_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(HUNTER_COST)
	return false


func do_action(idx: int) -> void:
	if idx != 0:
		return
	if not GameState.can_spend(HUNTER_COST):
		return
	GameState.spend(HUNTER_COST)
	if _producing:
		_queue_count += 1
	else:
		_start_production()


func get_status_text() -> String:
	if not _producing:
		return ""
	var t := "Building Hunter... %.0fs" % _produce_timer
	if _queue_count > 0:
		t += "  •  Queued: %d" % _queue_count
	return t


func _start_production() -> void:
	_producing = true
	_produce_timer = HUNTER_BUILD_TIME


func _physics_process(delta: float) -> void:
	# Production timer on the physics tick, not _process — CLAUDE.md Rule #2.
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_hunter()
			_producing = false
			if _queue_count > 0:
				_queue_count -= 1
				_start_production()


const SPAWN_JITTER := 24.0


func _spawn_hunter() -> void:
	if hunter_scene == null:
		return
	var h = hunter_scene.instantiate()
	# SimRng for spawn jitter — gameplay-affecting (CLAUDE.md Rule #1).
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	h.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(h)


func _draw_building_icon() -> void:
	var inner_size := Vector2(40.0, 26.0)
	draw_rect(Rect2(-inner_size / 2.0, inner_size), PALETTE_TRIBAL)


func _get_skin_path() -> String:
	return "res://assets/buildings/hunting_lodge.png"  # skin pass 2, 2026-06-11


func _get_faction_dressing() -> String:
	return "tribal"  # MapCraft C: spawn carries the faction identity
