class_name SettlementHub
extends "res://scripts/Building.gd"

const SPAWN_OFFSET := Vector2(0, 80)
const ABSOLUTE_RUNNER_CAP := 4

# Survivor roster (DESIGN_MASTER §7.3, connected 2026-06-10 on Matt's
# go). Data-driven rows like RitualSite's queue. Costs/times are balance-
# lab placeholders sized against the other factions' HQs; "few and
# precious" carried by the higher specialist prices, not unit scarcity.
# Old Scout/Engineer rows are superseded: Runner IS the Scout skeleton
# (SurvivorRunner extends Scout), Builder replaces the borrowed Engineer.
const CATALOG := {
	"runner": {"scene": preload("res://scenes/units/SurvivorRunner.tscn"), "cost": 50, "time": 8.0},
	"builder": {"scene": preload("res://scenes/units/Builder.tscn"), "cost": 50, "time": 8.0},
	"brawler": {"scene": preload("res://scenes/units/Brawler.tscn"), "cost": 50, "time": 8.0},
	"bolter": {"scene": preload("res://scenes/units/Bolter.tscn"), "cost": 75, "time": 10.0},
	"chemist": {"scene": preload("res://scenes/units/Chemist.tscn"), "cost": 90, "time": 12.0},
	"saboteur": {"scene": preload("res://scenes/units/Saboteur.tscn"), "cost": 100, "time": 12.0},
}

var _producing := false
var _produce_timer := 0.0
var _produce_what := ""
var _queue: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("settlement_hub")
	add_to_group("depot")
	add_to_group("hq")


func _available_items() -> Array:
	# Full roster, no tech gating in v1. Future gating candidates: bolter
	# behind a garrison, chemist behind the [OPEN] civilian system. The old
	# workshop gate was a Military cross-faction artifact — dropped.
	return CATALOG.keys()


func get_action_count() -> int:
	return _available_items().size()


func get_action_text(idx: int) -> String:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return ""
	var item: String = items[idx]
	# "Recruit", not "Build" — Survivors recruit people (and it reads better
	# than "Build Builder"). DESIGN_MASTER §7.3: units are civilians who join.
	return "Recruit %s (%d Salvage)" % [item.capitalize(), _cost_for(item)]


func _cost_for(item: String) -> int:
	return int(CATALOG.get(item, {}).get("cost", 0))


func get_action_available(idx: int) -> bool:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return false
	var item: String = items[idx]
	if item == "runner" and _runner_count() >= _runner_cap():
		return false
	return GameState.can_spend(_cost_for(item))


func _runner_count() -> int:
	# SurvivorRunner extends Scout, so it inherits the "scouts" group —
	# the safehouse-scaled economy cap carries over to the Runner intact.
	# PLAYER-owned only: with the Survivor AI wired in (2026-06-11), AI
	# runners share the group and must not eat the player's cap.
	var n: int = 0
	for sc in get_tree().get_nodes_in_group("scouts"):
		if is_instance_valid(sc) and sc.is_in_group("player_units"):
			n += 1
	return n


func _runner_cap() -> int:
	var safehouses: int = get_tree().get_nodes_in_group("safehouse").size()
	return min(2 + 2 * safehouses, ABSOLUTE_RUNNER_CAP)


func do_action(idx: int) -> void:
	var items = _available_items()
	if idx < 0 or idx >= items.size():
		return
	var item: String = items[idx]
	if item == "runner" and _runner_count() >= _runner_cap():
		return
	var cost: int = _cost_for(item)
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
	var t := "Building %s... %.0fs" % [_produce_what.capitalize(), _produce_timer]
	if _queue.size() > 0:
		t += "  •  Queued: %d" % _queue.size()
	return t


func _start_production(item: String) -> void:
	_producing = true
	_produce_what = item
	_produce_timer = float(CATALOG.get(item, {}).get("time", 8.0))


func _physics_process(delta: float) -> void:
	# D5 (AUDIT 2026-06-09): production is sim state — physics tick, not wall frames.
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
	var scene: PackedScene = CATALOG.get(item, {}).get("scene")
	if scene == null:
		return
	var u = scene.instantiate()
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	u.position = global_position + SPAWN_OFFSET + jitter
	get_parent().add_child(u)


func _draw_building_icon() -> void:
	draw_circle(Vector2.ZERO, 14.0, PALETTE_SURVIVOR)


func _get_skin_path() -> String:
	return "res://assets/buildings/settlement_hub.png"  # skin pass 2, 2026-06-11


func _get_faction_dressing() -> String:
	return "survivor"  # MapCraft C: spawn carries the faction identity
