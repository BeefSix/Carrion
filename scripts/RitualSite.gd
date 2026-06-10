class_name RitualSite
extends "res://scripts/Building.gd"

const SHAMAN_COST := 100
const SHAMAN_BUILD_TIME := 13.0
const CALLER_COST := 90        # CALLER_PLAN B2 (approved): the herder
const CALLER_BUILD_TIME := 15.0  # slow build — a deliberate commit
const SPAWN_OFFSET := Vector2(0, 80)

@export var shaman_scene: PackedScene
# Preloaded (not @export) so existing placed Ritual Sites don't need
# editor rewiring to gain the Caller row.
const CALLER_SCENE := preload("res://scenes/units/Caller.tscn")

var _producing := false
var _produce_what: String = "shaman"
var _produce_timer := 0.0
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("ritual_site")


func get_action_count() -> int:
	return 2


func get_action_text(idx: int) -> String:
	if idx == 0:
		return "Build Shaman (%d Salvage)" % SHAMAN_COST
	if idx == 1:
		return "Build Caller (%d Salvage)" % CALLER_COST
	return ""


func get_action_available(idx: int) -> bool:
	if idx == 0:
		return GameState.can_spend(SHAMAN_COST)
	if idx == 1:
		return GameState.can_spend(CALLER_COST)
	return false


func do_action(idx: int) -> void:
	var item: String = "shaman" if idx == 0 else ("caller" if idx == 1 else "")
	if item == "":
		return
	var cost: int = SHAMAN_COST if item == "shaman" else CALLER_COST
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
	var t := "Building %s... %.0fs" % ["Shaman" if _produce_what == "shaman" else "Caller", _produce_timer]
	if _queue.size() > 0:
		t += "  •  Queued: %d" % _queue.size()
	return t


func _start_production(item: String) -> void:
	_producing = true
	_produce_what = item
	_produce_timer = SHAMAN_BUILD_TIME if item == "shaman" else CALLER_BUILD_TIME


func _physics_process(delta: float) -> void:
	# Production timer on the physics tick — CLAUDE.md Rule #2.
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_unit_for(_produce_what)
			_producing = false
			if _queue.size() > 0:
				_start_production(_queue.pop_front())


const SPAWN_JITTER := 24.0


func _spawn_unit_for(item: String) -> void:
	var scene: PackedScene = shaman_scene if item == "shaman" else CALLER_SCENE
	if scene == null:
		return
	var s = scene.instantiate()
	# SimRng for spawn jitter — gameplay-affecting (CLAUDE.md Rule #1).
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	s.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(s)


func _draw_building_icon() -> void:
	# Three small circles arranged in triangle - ritual marker
	var r := 4.0
	draw_circle(Vector2(0, -8), r, PALETTE_TRIBAL)
	draw_circle(Vector2(-8, 6), r, PALETTE_TRIBAL)
	draw_circle(Vector2(8, 6), r, PALETTE_TRIBAL)


func _get_skin_path() -> String:
	return "res://assets/buildings/ritual_site.png"  # skin pass 2, 2026-06-11


func _get_faction_dressing() -> String:
	return "tribal"  # MapCraft C: spawn carries the faction identity
