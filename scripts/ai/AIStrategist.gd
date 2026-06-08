class_name AIStrategist
extends RefCounted

# Strategic layer for the AI. Decides WHAT to do over the next minutes — not the
# moment-to-moment positioning of units. Re-evaluated every ~5 seconds by the
# controller. For Phase 1 this is a hardcoded Military "Quick Looter Rush" build
# order followed by a simple build -> attack -> retreat -> attack posture loop.

enum State { BUILD, ATTACK, RETREAT }

const ATTACK_THRESHOLD := 6
const RETREAT_FRACTION := 0.6

# Each step: produced item name, salvage cost, build time in seconds. Items that
# require a Barracks are blocked until one exists; the controller is asked.
const BUILD_ORDER := [
	{ "item": "looter",   "cost": 50,  "time": 18.0, "needs_barracks": false },
	{ "item": "looter",   "cost": 50,  "time": 18.0, "needs_barracks": false },
	{ "item": "barracks", "cost": 200, "time": 50.0, "needs_barracks": false },
	{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_barracks": true },
	{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_barracks": true },
	{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_barracks": true },
	{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_barracks": true },
]

# After the canonical build order is exhausted, the AI keeps producing this item
# to refill its army indefinitely.
const SUSTAIN_ITEM := { "item": "rifleman", "cost": 75, "time": 25.0, "needs_barracks": true }

# H2 stall-recovery templates - used when economy / structure assumptions of
# the canonical BUILD_ORDER no longer hold. Same parameters as the build-order
# rows; just re-emitted without consuming _step so we don't skip canonical
# tasks while recovering.
const LOOTER_RECOVERY_TASK := { "item": "looter",   "cost": 50,  "time": 18.0, "needs_barracks": false }
const BARRACKS_RECOVERY_TASK := { "item": "barracks", "cost": 200, "time": 50.0, "needs_barracks": false }

# The build order assumes ~2 Looters; below this we treat the economy as
# stalled and force a recovery Looter regardless of where we are in the order.
# Set to 1 (not 2) so a single living Looter still feeds the canonical pipeline -
# only a fully dead economy interrupts.
const ECONOMY_FLOOR := 1

# Cached script identities for stall-recovery counts. Lazy-loaded because they
# pull in scene resources that aren't needed until the first evaluate.
var _looter_script = null

var controller: AIController = null
var _step: int = 0
var _state: int = State.BUILD
var _peak_combat: int = 0


func evaluate() -> void:
	if controller == null:
		return
	_advance_production()
	_update_posture()


func _advance_production() -> void:
	if controller.is_producing():
		return
	var task: Dictionary = _next_task()
	if task.is_empty():
		return
	if task.needs_barracks and not controller.has_barracks():
		return
	if not controller.spend_for_production(task.cost):
		return
	controller.start_production(task.item, task.time)
	# Only advance the canonical build order when we ran a canonical task.
	# Recovery tasks (looter / barracks replacements) are tagged so the step
	# counter stays put and the post-recovery pipeline resumes where it left off.
	if not task.get("recovery", false) and _step < BUILD_ORDER.size():
		_step += 1


func _next_task() -> Dictionary:
	# H2 recovery layer takes priority over the canonical build order:
	#   1. If the economy died (no Looters), build a Looter regardless of step.
	#   2. If we're past the Barracks step but the Barracks is gone, build one.
	# Both cases would otherwise stall forever - the canonical order would
	# advance to a step it couldn't afford or that needs the missing Barracks.
	if _looter_script == null:
		_looter_script = load("res://scripts/Looter.gd")
	var looter_count: int = controller.count_units_with_script(_looter_script)
	if looter_count < ECONOMY_FLOOR:
		return _recovery(LOOTER_RECOVERY_TASK)
	# "We've already moved past the Barracks build" = step has advanced past
	# the Barracks index. _step is the NEXT task to run; if we're at or past
	# index 3 we've already executed step 2 (the Barracks).
	if _step >= 3 and not controller.has_barracks():
		return _recovery(BARRACKS_RECOVERY_TASK)
	if _step < BUILD_ORDER.size():
		return BUILD_ORDER[_step]
	return SUSTAIN_ITEM


func _recovery(template: Dictionary) -> Dictionary:
	# Tag a copy of the template so _advance_production knows not to bump _step.
	var task: Dictionary = template.duplicate()
	task["recovery"] = true
	return task


func _update_posture() -> void:
	var combat_count: int = controller.get_combat_count()
	if combat_count > _peak_combat:
		_peak_combat = combat_count

	match _state:
		State.BUILD:
			if combat_count >= ATTACK_THRESHOLD:
				_enter_attack()
		State.ATTACK:
			if combat_count > 0 and combat_count < int(_peak_combat * RETREAT_FRACTION):
				_enter_retreat()
			elif combat_count == 0:
				_enter_retreat()
		State.RETREAT:
			if combat_count >= ATTACK_THRESHOLD:
				_enter_attack()


func _enter_attack() -> void:
	_state = State.ATTACK
	_peak_combat = controller.get_combat_count()
	controller.tactician.set_attack_order(controller.get_enemy_hq_position())


func _enter_retreat() -> void:
	_state = State.RETREAT
	_peak_combat = 0
	controller.tactician.set_retreat_order(controller.get_hq_position())


func get_state_name() -> String:
	match _state:
		State.ATTACK: return "ATTACK"
		State.RETREAT: return "RETREAT"
		_: return "BUILD"
