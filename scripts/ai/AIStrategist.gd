class_name AIStrategist
extends RefCounted

# Strategic layer for the AI. Decides WHAT to do over the next minutes — not the
# moment-to-moment positioning of units. Re-evaluated every ~5 seconds by the
# controller.
#
# A1 (AI_OVERHAUL_PLAN.md, approved 2026-06-10): all faction-specific DATA
# (build order, sustain composition, thresholds, recovery templates) lives in
# AIProfiles.gd; this file contains zero faction knowledge. Production
# decisions are evaluated as a strict-priority GOAL STACK (first unmet goal
# wins — deterministic, no scoring floats):
#   1. SURVIVE            (A2 — base under attack preempts; not yet wired)
#   2. ECONOMY FLOOR      (dead economy -> recovery worker, H2)
#   3. ECONOMY GROWTH     (A3 — worker target curve; not yet wired)
#   4. PRODUCTION/TECH    (canonical build order + production-building recovery)
#   5. ARMY               (sustain composition, round-robin)
# The BUILD/ATTACK/RETREAT posture machine below is the army layer underneath:
# goals decide what to SPEND, posture decides where the army STANDS.
#
# A1 is regression-gated: with the Military profile this emits the exact
# decision sequence of the pre-profile code (verified by identical seed-42
# hash streams).

enum State { BUILD, ATTACK, RETREAT }

# Preloaded (not class_name lookup) so headless runs don't depend on the
# editor's global-class cache being fresh.
const Profiles := preload("res://scripts/ai/AIProfiles.gd")

# Faction strategy data (see AIProfiles.gd for key documentation). Assigned
# by the controller at _ready from its faction; defaults to Military so a
# bare strategist in a test scene still functions.
var profile: Dictionary = Profiles.MILITARY

# Cached script identity for the economy-floor count. Lazy-loaded from the
# profile because it pulls in scene resources not needed until first evaluate.
var _worker_script = null

var controller: AIController = null
var _step: int = 0
var _sustain_idx: int = 0  # round-robin cursor over profile.sustain
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
	if task.needs_production_building and not controller.has_barracks():
		return
	if not controller.spend_for_production(task.cost):
		return
	controller.start_production(task.item, task.time)
	# Cursor bookkeeping AFTER the spend succeeded: the canonical step only
	# advances when a canonical task ran (recovery tasks are tagged so the
	# pipeline resumes where it left off — H2), and the sustain round-robin
	# only rotates when a sustain task actually started.
	if task.get("sustain", false):
		var sustain: Array = profile["sustain"]
		_sustain_idx = (_sustain_idx + 1) % sustain.size()
	elif not task.get("recovery", false) and _step < profile["build_order"].size():
		_step += 1


func _next_task() -> Dictionary:
	# THE GOAL STACK (strict priority — see header). Each goal either returns
	# a task or falls through to the next. Order is load-bearing: it must
	# match the pre-profile decision sequence exactly (A1 regression bar).
	#
	# Goal 1 — SURVIVE: A2 inserts the defend preemption here.
	#
	# Goal 2 — ECONOMY FLOOR (H2): if the economy died, a recovery worker
	# preempts everything; the canonical order would otherwise advance to
	# steps it can never afford.
	if _worker_script == null:
		_worker_script = load(profile["worker_script"])
	var worker_count: int = controller.count_units_with_script(_worker_script)
	if worker_count < int(profile["economy_floor"]):
		return _recovery(profile["recovery_worker"])
	# Goal 3 — ECONOMY GROWTH: A3 inserts the worker target curve here.
	#
	# Goal 4 — PRODUCTION/TECH: production-building recovery first ("we've
	# already moved past the build step but the building is gone" — _step is
	# the NEXT task, so being at/past production_building_step means the
	# building was built and has since died), then the canonical order.
	if _step >= int(profile["production_building_step"]) and not controller.has_barracks():
		return _recovery(profile["recovery_production_building"])
	var build_order: Array = profile["build_order"]
	if _step < build_order.size():
		return build_order[_step]
	# Goal 5 — ARMY: sustain composition, round-robin (rotated in
	# _advance_production only when the task actually starts).
	var sustain: Array = profile["sustain"]
	var task: Dictionary = sustain[_sustain_idx].duplicate()
	task["sustain"] = true
	return task


func _recovery(template: Dictionary) -> Dictionary:
	# Tag a copy of the template so _advance_production knows not to bump _step.
	var task: Dictionary = template.duplicate()
	task["recovery"] = true
	return task


func _update_posture() -> void:
	var combat_count: int = controller.get_combat_count()
	if combat_count > _peak_combat:
		_peak_combat = combat_count

	var attack_threshold: int = int(profile["attack_threshold"])
	var retreat_fraction: float = float(profile["retreat_fraction"])
	match _state:
		State.BUILD:
			if combat_count >= attack_threshold:
				_enter_attack()
		State.ATTACK:
			if combat_count > 0 and combat_count < int(_peak_combat * retreat_fraction):
				_enter_retreat()
			elif combat_count == 0:
				_enter_retreat()
		State.RETREAT:
			if combat_count >= attack_threshold:
				_enter_attack()


func _enter_attack() -> void:
	var prev: String = get_state_name()
	_state = State.ATTACK
	var army_size: int = controller.get_combat_count()
	_peak_combat = army_size
	var target: Vector2 = controller.get_enemy_hq_position()
	controller.tactician.set_attack_order(target)
	# Telemetry: surface the transition + the parameters of the order so the
	# timeline can answer "did this AI ever attack, and with what?". Logged
	# AFTER the state change so the snapshot shows the new state.
	MatchStats.log_event(&"ai_posture_changed", {
		"controller": controller.get_controller_id(),
		"from": prev,
		"to": get_state_name(),
	})
	MatchStats.log_event(&"ai_attack_ordered", {
		"controller": controller.get_controller_id(),
		"target_pos": [target.x, target.y],
		"army_size": army_size,
	})


func _enter_retreat() -> void:
	var prev: String = get_state_name()
	_state = State.RETREAT
	_peak_combat = 0
	controller.tactician.set_retreat_order(controller.get_hq_position())
	MatchStats.log_event(&"ai_posture_changed", {
		"controller": controller.get_controller_id(),
		"from": prev,
		"to": get_state_name(),
	})


func get_step() -> int:
	# Public accessor for the build-order step counter. Consumed by
	# AIController._emit_phase_snapshot so the JSONL records progress
	# through BUILD_ORDER without leaking the field name to the rest of
	# the codebase.
	return _step


func get_state_name() -> String:
	match _state:
		State.ATTACK: return "ATTACK"
		State.RETREAT: return "RETREAT"
		_: return "BUILD"
