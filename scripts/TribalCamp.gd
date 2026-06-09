class_name TribalCamp
extends "res://scripts/Building.gd"

const WALKER_COST := 50
const WALKER_BUILD_TIME := 7.0
const HUNTING_LODGE_COST := 150
const HUNTING_LODGE_BUILD_TIME := 45.0
const RITUAL_SITE_COST := 200
const RITUAL_SITE_BUILD_TIME := 50.0
const WALKER_SPAWN_OFFSET := Vector2(0, 80)
const HUNTING_LODGE_SPAWN_OFFSET := Vector2(-140, 0)
const RITUAL_SITE_SPAWN_OFFSET := Vector2(140, 0)

@export var walker_scene: PackedScene
@export var hunting_lodge_scene: PackedScene
@export var ritual_site_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("tribal_camp")
	add_to_group("hq")


func get_action_count() -> int:
	return 3


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Walker (%d Salvage)" % WALKER_COST
	if idx == 1:
		return "Build Hunting Lodge (%d Salvage)" % HUNTING_LODGE_COST
	if idx == 2:
		return "Build Ritual Site (%d Salvage)" % RITUAL_SITE_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(WALKER_COST)
	if idx == 1:
		return GameState.can_spend(HUNTING_LODGE_COST)
	if idx == 2:
		return GameState.can_spend(RITUAL_SITE_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("walker", WALKER_COST)
	elif idx == 1:
		_queue_item("hunting_lodge", HUNTING_LODGE_COST)
	elif idx == 2:
		_queue_item("ritual_site", RITUAL_SITE_COST)


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name := "Walker"
	match _produce_what:
		"hunting_lodge":
			pretty_name = "Hunting Lodge"
		"ritual_site":
			pretty_name = "Ritual Site"
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
	match item:
		"walker":
			_produce_timer = WALKER_BUILD_TIME
		"hunting_lodge":
			_produce_timer = HUNTING_LODGE_BUILD_TIME
		"ritual_site":
			_produce_timer = RITUAL_SITE_BUILD_TIME
		_:
			_produce_timer = WALKER_BUILD_TIME


func _physics_process(delta: float) -> void:
	# Production timer runs on the physics tick (sim state mutation, CLAUDE.md
	# Rule #2) — not _process(delta), which is wall-time-coupled and varies
	# with framerate.
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
	match item:
		"walker":
			if walker_scene != null:
				var w = walker_scene.instantiate()
				# SimRng for spawn jitter — gameplay-affecting (positions feed
				# perception checks, pathing). CLAUDE.md Rule #1.
				var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
				w.position = global_position + WALKER_SPAWN_OFFSET + jitter
				get_parent().add_child(w)
		"hunting_lodge":
			if hunting_lodge_scene != null:
				var hl = hunting_lodge_scene.instantiate()
				hl.position = global_position + HUNTING_LODGE_SPAWN_OFFSET
				get_parent().add_child(hl)
				# H10: needed so is_owned_by_player picks this up. Player TribalCamp
				# is the only spawner today (AIController doesn't run Tribal).
				hl.add_to_group("player_buildings")
				_request_nav_rebake()
		"ritual_site":
			if ritual_site_scene != null:
				var rs = ritual_site_scene.instantiate()
				rs.position = global_position + RITUAL_SITE_SPAWN_OFFSET
				get_parent().add_child(rs)
				rs.add_to_group("player_buildings")
				_request_nav_rebake()


func _request_nav_rebake() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_TRIBAL)
