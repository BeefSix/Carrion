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

enum State { BUILD, ATTACK, RETREAT, DEFEND }

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
var _last_forcespawn_sim: float = -1000.0  # A4 ritual cadence anchor
var _last_harass_sim: float = -1000.0      # A5 harass cadence anchor


func evaluate() -> void:
	if controller == null:
		return
	_advance_production()
	_update_posture()
	_direct_shaman()
	_direct_harass()


func _direct_harass() -> void:
	# A5 (approved defaults). Every harass_interval once harass_start has
	# passed, peel harass_squad units at the most exposed enemy worker.
	# Conditions: never while DEFENDing (home first), and only when the
	# army is at/above the attack threshold so harassment is a tax on
	# strength, not a suicide of the last defenders.
	if _state == State.DEFEND:
		return
	var now: float = GameState.sim_seconds()
	if now < float(profile.get("harass_start", 1e12)):
		return
	if now - _last_harass_sim < float(profile.get("harass_interval", 90.0)):
		return
	if controller.get_combat_count() < int(profile["attack_threshold"]):
		return
	var target = controller.find_exposed_enemy_worker()
	if target == null:
		return
	var sent: int = controller.tactician.dispatch_harass(target.global_position, int(profile.get("harass_squad", 2)))
	if sent == 0:
		return
	_last_harass_sim = now
	MatchStats.log_event(&"ai_harass_ordered", {
		"controller": controller.get_controller_id(),
		"target_pos": [target.global_position.x, target.global_position.y],
		"squad": sent,
	})


func _direct_shaman() -> void:
	# A4 Tribal identity: an IDLE Shaman is a wasted Shaman. Send it to
	# ritual at the infested building nearest the enemy HQ (approved
	# default C — deterministic, dramatic, teaches the player what
	# force-spawn does). The Shaman handles its own approach + channel +
	# owner-aware salvage; re-issued only when idle again, so a 5s eval
	# cadence can't interrupt a ritual in progress.
	if not profile.get("uses_shaman", false):
		return
	if GameState.sim_seconds() < float(profile.get("forcespawn_start", 0.0)):
		return
	if GameState.sim_seconds() - _last_forcespawn_sim < float(profile.get("forcespawn_interval", 45.0)):
		return
	var shaman = controller.find_idle_shaman()
	if shaman == null:
		return
	var target = controller.find_forcespawn_target()
	if target == null:
		return
	var src: String = CommandBus.SRC_AI_PLAYER_SLOT if controller.as_player_slot else CommandBus.SRC_AI_OPPOSING
	CommandBus.issue("force_spawn", shaman, {"target": target}, src)
	_last_forcespawn_sim = GameState.sim_seconds()
	MatchStats.log_event(&"ai_forcespawn_ordered", {
		"controller": controller.get_controller_id(),
		"target_pos": [target.position.x, target.position.y],
	})


func _advance_production() -> void:
	if controller.is_producing():
		return
	var task: Dictionary = _next_task()
	if task.is_empty():
		return
	# .get, not dot access — rows only carry the gate keys they need (the
	# Tribal shaman row has needs_tech_building but no production key).
	if task.get("needs_production_building", false) and not controller.has_barracks():
		return
	if task.get("needs_tech_building", false) and not controller.has_tech_building():
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
		_sustain_idx = (int(task.get("sustain_idx", _sustain_idx)) + 1) % sustain.size()
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
	# Goal 3 — ECONOMY GROWTH (A3): grow workers toward the profile's
	# [sim_minute, count] curve. Tagged like a recovery so the canonical
	# build-order step doesn't advance — growth workers are EXTRA, the
	# opening stays intact. Sits above PRODUCTION so a starved economy
	# gets its worker before the next army row (workers pay for the army).
	if worker_count < _worker_target_now():
		return _recovery(profile["recovery_worker"])
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
	#
	# Affordability fall-through (A3 lab finding): a strict round-robin
	# head-of-line blocks on the expensive row — the AI parked on the
	# 225-cost HG while income trickled, army flatlined at 4, never
	# attacked. Deterministic fix: scan forward from the cursor for the
	# first AFFORDABLE row; if none, wait on the cursor row (saving is
	# still sometimes right). Effect: rich = the profile ratio, poor =
	# cheap units keep flowing. Rotation happens from the row that
	# actually STARTED (sustain_idx tag), so the mix stays fair.
	var sustain: Array = profile["sustain"]
	var pick: int = _sustain_idx
	for offset in range(sustain.size()):
		var idx: int = (_sustain_idx + offset) % sustain.size()
		if controller.can_afford(int(sustain[idx]["cost"])):
			pick = idx
			break
	var task: Dictionary = sustain[pick].duplicate()
	task["sustain"] = true
	task["sustain_idx"] = pick
	return task


func _worker_target_now() -> int:
	# Latest [minute, count] step whose minute has passed. The list is
	# ordered; a linear walk over <=4 entries each strategic eval is free.
	var minutes: float = GameState.sim_seconds() / 60.0
	var target: int = 0
	for step in profile["worker_targets"]:
		if minutes >= float(step[0]):
			target = int(step[1])
	return target


func _recovery(template: Dictionary) -> Dictionary:
	# Tag a copy of the template so _advance_production knows not to bump _step.
	var task: Dictionary = template.duplicate()
	task["recovery"] = true
	return task


func _update_posture() -> void:
	var combat_count: int = controller.get_combat_count()
	if combat_count > _peak_combat:
		_peak_combat = combat_count

	# A2 — SURVIVE preempts everything (goal 1 of the stack, posture form).
	# "Base under attack" = a building took damage within defend_cooldown
	# sim-seconds. While threatened: hold/refresh the DEFEND order toward
	# the latest threat position. Once quiet for the cooldown: stand down
	# to BUILD and let the thresholds below re-trigger ATTACK naturally —
	# an army that was mid-commit resumes the commit on the next eval.
	var base_threatened: bool = controller.sim_since_base_damage() <= float(profile["defend_cooldown"])
	if base_threatened:
		if _state != State.DEFEND:
			_enter_defend()
		else:
			# Refresh: a moving attacker drags the rally point with it.
			controller.tactician.set_defend_order(controller.get_base_threat_pos())
		return
	elif _state == State.DEFEND:
		_exit_defend()
		# fall through — thresholds may immediately re-enter ATTACK below

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


func _enter_defend() -> void:
	var prev: String = get_state_name()
	_state = State.DEFEND
	var threat: Vector2 = controller.get_base_threat_pos()
	controller.tactician.set_defend_order(threat)
	MatchStats.log_event(&"ai_posture_changed", {
		"controller": controller.get_controller_id(),
		"from": prev,
		"to": get_state_name(),
	})
	MatchStats.log_event(&"ai_defend_ordered", {
		"controller": controller.get_controller_id(),
		"threat_pos": [threat.x, threat.y],
		"army_size": controller.get_combat_count(),
	})


func _exit_defend() -> void:
	var prev: String = get_state_name()
	_state = State.BUILD
	controller.tactician.set_hold_order()
	MatchStats.log_event(&"ai_posture_changed", {
		"controller": controller.get_controller_id(),
		"from": prev,
		"to": get_state_name(),
	})


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
		State.DEFEND: return "DEFEND"
		_: return "BUILD"
