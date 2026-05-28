class_name Barracks
extends "res://scripts/Building.gd"

const RIFLEMAN_COST := 75
const RIFLEMAN_BUILD_TIME := 25.0
const HEAVY_GUNNER_COST := 225
const HEAVY_GUNNER_BUILD_TIME := 40.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var rifleman_scene: PackedScene
@export var heavy_gunner_scene: PackedScene

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []

# Decay emission (see CommandPost.gd for the same constants and notes).
const DECAY_RADIUS_BASE := 4.0
const DECAY_RADIUS_CAP := 12.0
const DECAY_RADIUS_GROWTH_PER_MIN := 0.5
var _time_alive: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("decay_emitter")


func get_decay_radius() -> float:
	var grown: float = DECAY_RADIUS_BASE + (_time_alive / 60.0) * DECAY_RADIUS_GROWTH_PER_MIN
	return clamp(grown, DECAY_RADIUS_BASE, DECAY_RADIUS_CAP)


func get_action_count() -> int:
	return 2


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Rifleman (%d Salvage)" % RIFLEMAN_COST
	if idx == 1:
		return "Build Heavy Gunner (%d Salvage)" % HEAVY_GUNNER_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(RIFLEMAN_COST)
	if idx == 1:
		return GameState.can_spend(HEAVY_GUNNER_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("rifleman", RIFLEMAN_COST)
	elif idx == 1:
		_queue_item("heavy_gunner", HEAVY_GUNNER_COST)


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name: String = "Rifleman" if _produce_what == "rifleman" else "Heavy Gunner"
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
	_produce_timer = RIFLEMAN_BUILD_TIME if item == "rifleman" else HEAVY_GUNNER_BUILD_TIME


func _process(delta: float) -> void:
	_time_alive += delta
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_item(_produce_what)
			_producing = false
			if _queue.size() > 0:
				var next_item: String = _queue.pop_front()
				_start_production(next_item)


func _draw_building_icon() -> void:
	var inner_size := Vector2(40.0, 26.0)
	draw_rect(Rect2(-inner_size / 2.0, inner_size), PALETTE_MILITARY)


func _spawn_item(item: String) -> void:
	var scene: PackedScene = null
	if item == "rifleman":
		scene = rifleman_scene
	elif item == "heavy_gunner":
		scene = heavy_gunner_scene
	if scene == null:
		return
	var u = scene.instantiate()
	u.position = global_position + SPAWN_OFFSET
	get_parent().add_child(u)
