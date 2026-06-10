class_name Barracks
extends "res://scripts/Building.gd"

const RIFLEMAN_COST := 75
const RIFLEMAN_BUILD_TIME := 8.0
const HEAVY_GUNNER_COST := 225
const HEAVY_GUNNER_BUILD_TIME := 13.0
const MEDIC_COST := 100
const MEDIC_BUILD_TIME := 10.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var rifleman_scene: PackedScene
@export var heavy_gunner_scene: PackedScene
# Preloaded (not @export) so existing placed Barracks scenes don't need
# editor rewiring to gain the Medic row.
const MEDIC_SCENE := preload("res://scenes/units/Medic.tscn")

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
	return 3


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Rifleman (%d Salvage)" % RIFLEMAN_COST
	if idx == 1:
		return "Build Heavy Gunner (%d Salvage)" % HEAVY_GUNNER_COST
	if idx == 2:
		return "Build Medic (%d Salvage)" % MEDIC_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(RIFLEMAN_COST)
	if idx == 1:
		return GameState.can_spend(HEAVY_GUNNER_COST)
	if idx == 2:
		return GameState.can_spend(MEDIC_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("rifleman", RIFLEMAN_COST)
	elif idx == 1:
		_queue_item("heavy_gunner", HEAVY_GUNNER_COST)
	elif idx == 2:
		_queue_item("medic", MEDIC_COST)


const PRETTY_NAMES := {"rifleman": "Rifleman", "heavy_gunner": "Heavy Gunner", "medic": "Medic"}
const BUILD_TIMES := {"rifleman": RIFLEMAN_BUILD_TIME, "heavy_gunner": HEAVY_GUNNER_BUILD_TIME, "medic": MEDIC_BUILD_TIME}


func get_status_text() -> String:
	if not _producing:
		return ""
	var pretty_name: String = PRETTY_NAMES.get(_produce_what, _produce_what)
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
	_produce_timer = BUILD_TIMES.get(item, RIFLEMAN_BUILD_TIME)


func _physics_process(delta: float) -> void:
	# D5 (AUDIT 2026-06-09): production is sim state — physics tick, not wall frames.
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


const SPAWN_JITTER := 24.0


func _spawn_item(item: String) -> void:
	var scene: PackedScene = null
	if item == "rifleman":
		scene = rifleman_scene
	elif item == "heavy_gunner":
		scene = heavy_gunner_scene
	elif item == "medic":
		scene = MEDIC_SCENE
	if scene == null:
		return
	var u = scene.instantiate()
	# Jitter so back-to-back spawns don't stack on the same pixel and have the
	# physics solver separate them in random directions.
	# SimRng (CI 2026-06-09): spawn position is sim state — bare randf_range
	# here was the same divergence class the AIController/Lootable fixes hit.
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	u.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(u)


func _get_skin_path() -> String:
	return "res://assets/buildings/barracks.png"  # skin pass 2, 2026-06-11


func _get_faction_dressing() -> String:
	return "military"  # MapCraft C: spawn carries the faction identity
