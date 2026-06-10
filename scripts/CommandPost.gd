class_name CommandPost
extends "res://scripts/Building.gd"

const LOOTER_COST := 50
const LOOTER_BUILD_TIME := 6.0
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

# Decay emission: radius grows from DECAY_RADIUS_BASE to DECAY_RADIUS_CAP at
# DECAY_RADIUS_GROWTH tiles per minute (per PROTOTYPE_PLAN item 32).
const DECAY_RADIUS_BASE := 4.0
const DECAY_RADIUS_CAP := 12.0
const DECAY_RADIUS_GROWTH_PER_MIN := 0.5
var _time_alive: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("command_post")
	add_to_group("hq")
	add_to_group("decay_emitter")


func get_decay_radius() -> float:
	var grown: float = DECAY_RADIUS_BASE + (_time_alive / 60.0) * DECAY_RADIUS_GROWTH_PER_MIN
	return clamp(grown, DECAY_RADIUS_BASE, DECAY_RADIUS_CAP)


# Worker-built construction (2026-06-10): the Barracks row moved onto the
# Looter (SC model — select a Looter, place a ghost, it builds). The CP
# produces UNITS only now.
func get_action_count() -> int:
	return 1


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Looter (%d Salvage)" % LOOTER_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(LOOTER_COST)
	return false


func do_action(idx: int) -> void:
	if idx == 0:
		_queue_item("looter", LOOTER_COST)


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
	draw_circle(Vector2.ZERO, 14.0, PALETTE_MILITARY)


const SPAWN_JITTER := 24.0


func _spawn_item(item: String) -> void:
	if item == "looter":
		if looter_scene != null:
			var l = looter_scene.instantiate()
			# Jitter so multiple Looters don't spawn on top of each other -
			# overlapping CharacterBody2D shapes get separated by the physics
			# solver in unpredictable directions, which is what produced the
			# "second looter ran left off the screen" report.
			l.position = global_position + LOOTER_SPAWN_OFFSET + _spawn_jitter()
			get_parent().add_child(l)
	elif item == "barracks":
		if barracks_scene != null:
			var b = barracks_scene.instantiate()
			b.position = global_position + BARRACKS_SPAWN_OFFSET
			get_parent().add_child(b)
			# Player CommandPost is the only spawner of this scene (AI runs
			# its own production loop in AIController and tags ai_buildings
			# there); tagging is needed so GameState.is_owned_by_player works
			# for ownership gates in SelectionManager / HUD / Projectile (H10).
			b.add_to_group("player_buildings")
			_request_nav_rebake()


func _spawn_jitter() -> Vector2:
	return Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))


func _request_nav_rebake() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")
