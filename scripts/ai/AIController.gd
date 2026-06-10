class_name AIController
extends Node

# Top-level AI node. Sits in the scene tree, runs its own _process loop, owns one
# Strategist + one Tactician (composition, not inheritance). Spawns its own HQ at
# the assigned spawn position and manages its own salvage pool independently of
# GameState — same costs as the player, no resource cheats, but tracked in a
# separate variable so player UI is unaffected.

const STRATEGIC_INTERVAL := 5.0
const TACTICAL_INTERVAL := 1.0

const CP_SCENE := preload("res://scenes/buildings/CommandPost.tscn")
const BARRACKS_SCENE := preload("res://scenes/buildings/Barracks.tscn")
const LOOTER_SCENE := preload("res://scenes/units/Looter.tscn")
const RIFLEMAN_SCENE := preload("res://scenes/units/Rifleman.tscn")
const HEAVY_GUNNER_SCENE := preload("res://scenes/units/HeavyGunner.tscn")
# A4: Tribal roster + structures.
const TC_SCENE := preload("res://scenes/buildings/TribalCamp.tscn")
const SH_SCENE := preload("res://scenes/buildings/SettlementHub.tscn")
const SURVIVOR_RUNNER_SCENE := preload("res://scenes/units/SurvivorRunner.tscn")
const BOLTER_SCENE := preload("res://scenes/units/Bolter.tscn")
const BRAWLER_SCENE := preload("res://scenes/units/Brawler.tscn")
const CHEMIST_SCENE := preload("res://scenes/units/Chemist.tscn")
const FARM_SCENE := preload("res://scenes/buildings/Farm.tscn")
const RADIO_SCENE := preload("res://scenes/buildings/RadioStation.tscn")
const HUNTING_LODGE_SCENE := preload("res://scenes/buildings/HuntingLodge.tscn")
const RITUAL_SITE_SCENE := preload("res://scenes/buildings/RitualSite.tscn")
const WALKER_SCENE := preload("res://scenes/units/Walker.tscn")
const HUNTER_SCENE := preload("res://scenes/units/Hunter.tscn")
const SHAMAN_SCENE := preload("res://scenes/units/Shaman.tscn")
const SHAMAN_SCRIPT := preload("res://scripts/Shaman.gd")
const TECH_SPAWN_OFFSET := Vector2(-140, 0)  # ritual site west of camp (lodge takes east)

const LOOTER_SPAWN_OFFSET := Vector2(0, 80)
const RIFLEMAN_SPAWN_OFFSET := Vector2(0, 80)
const BARRACKS_SPAWN_OFFSET := Vector2(140, 0)

@export var faction: int = 0  # GameState.Faction.MILITARY = 0
@export var spawn_position: Vector2
@export var enemy_hq_position: Vector2
# AI-vs-AI: when true, this controller takes the "player slot" - its units and
# buildings get tagged into player_units/player_buildings and it registers its
# HQ via Main.set_player_hq instead of set_opposing_hq. The ownership/hostility
# helper then sees one team as player and the other as ai, so the existing
# win-condition + GameState.is_hostile logic works unchanged.
@export var as_player_slot: bool = false

var salvage: int = 200
var strategist: AIStrategist
var tactician: AITactician

const PHASE_SNAPSHOT_INTERVAL := 10.0  # sim seconds between ai_phase snapshots
const LOOTER_SCRIPT := preload("res://scripts/Looter.gd")

# Sim-time anchors for the three periodic loops (NOT delta-accumulating
# timers). Pre-fix, accumulating _process delta at Engine.time_scale = 8x
# made strategist evaluate ~8x more often per sim-second than STRATEGIC_INTERVAL
# implied (delta is scaled by time_scale; sim_seconds advances independently
# at 60 ticks/sec wall regardless of time_scale). Anchoring on sim_seconds()
# gives a stable cadence regardless of time_scale.
var _next_strategic_sim: float = 0.0
var _next_tactical_sim: float = 0.0
var _next_phase_snapshot_sim: float = 0.0
var _hq: Node2D = null
# Production building: Barracks (Military) or Hunting Lodge (Tribal). The
# name predates A4; has_barracks() is the generic "production building
# exists" check both profiles gate on.
var _barracks: Node2D = null
# A4: tech building — Ritual Site (Tribal). Gates shaman rows.
var _tech_building: Node2D = null

var _producing: bool = false
var _producing_what: String = ""
var _production_timer: float = 0.0

# A2 base-threat memory. Updated by notify_building_damaged (called from
# Building.take_damage on owner-tagged buildings); read by the strategist's
# SURVIVE posture check. Sim-time anchored, no polling.
var _last_base_damage_sim: float = -1000.0
var _base_threat_pos: Vector2 = Vector2.ZERO

# Group names cached at _ready from as_player_slot so the rest of the file
# doesn't have to branch at every tag site.
var _unit_group: String = "ai_units"
var _building_group: String = "ai_buildings"


func _ready() -> void:
	add_to_group("ai_controller")
	if as_player_slot:
		_unit_group = "player_units"
		_building_group = "player_buildings"
	strategist = AIStrategist.new()
	strategist.controller = self
	# A1: faction strategy is data — the strategist reads a profile and
	# carries zero faction knowledge itself. A4 adds the Tribal profile.
	# (Preload, not class_name — headless cache-independence.)
	strategist.profile = preload("res://scripts/ai/AIProfiles.gd").profile_for(faction)
	tactician = AITactician.new()
	tactician.controller = self
	_spawn_hq()


func _physics_process(delta: float) -> void:
	# D7 (AUDIT 2026-06-09): moved from _process. Production completion
	# spawns units = sim state; on raw _process delta the spawn TICK varied
	# between runs (frame-timing noise), which the record-vs-record CI
	# caught as the tick-180 divergence — two same-seed runs disagreed on
	# when the AI's first Looter landed. On the physics tick the countdown
	# is identical across runs. Also fixes the time_scale skew where AI
	# production ran 8x faster per sim-second in the lab than the player's.
	#
	# Replay: AI controllers must NOT make new decisions (the recorded
	# commands drive playback). Skip strategist/tactician evaluation
	# entirely. Production countdown stays off too so spawned units don't
	# diverge from the recorded ordinal sequence.
	if ReplayRecorder.is_playing:
		return
	_tick_production(delta)

	# H11: once the AI HQ is destroyed, stop the strategist/tactician loops
	# cold. The match is effectively over (Main's win-condition check will
	# overlay victory shortly) but any production / movement issued in this
	# window dereferences the freed HQ.
	if not is_alive():
		return

	var now_sim: float = GameState.sim_seconds()
	if now_sim >= _next_strategic_sim:
		_next_strategic_sim = now_sim + STRATEGIC_INTERVAL
		strategist.evaluate()
	if now_sim >= _next_tactical_sim:
		_next_tactical_sim = now_sim + TACTICAL_INTERVAL
		tactician.evaluate()
	if now_sim >= _next_phase_snapshot_sim:
		_next_phase_snapshot_sim = now_sim + PHASE_SNAPSHOT_INTERVAL
		_emit_phase_snapshot()


func is_alive() -> bool:
	return _hq != null and is_instance_valid(_hq)


# Stable controller identity for the telemetry stream. "player" = the AI
# driving the player slot in AI-vs-AI mode; "ai" = the opposing slot or
# the only AI in single-AI mode. Reads of the JSONL key off this string
# so both sides can be charted on one timeline.
func get_controller_id() -> String:
	return "player" if as_player_slot else "ai"


func _emit_phase_snapshot() -> void:
	# A4: count the PROFILE's worker (Walker for Tribal, Looter for
	# Military) — the hardcoded Looter count read 0 for Tribal and hid the
	# economy from telemetry.
	if _worker_script_cached == null and strategist != null:
		_worker_script_cached = load(strategist.profile["worker_script"])
	MatchStats.log_event(&"ai_phase", {
		"controller": get_controller_id(),
		"step": strategist.get_step() if strategist != null else -1,
		"state": strategist.get_state_name() if strategist != null else "UNKNOWN",
		"salvage": salvage,
		"looters": count_units_with_script(_worker_script_cached),
		"combat": get_combat_count(),
		"has_barracks": has_barracks(),
	})


var _worker_script_cached = null


# ---------- Strategist-facing API (defense, A2) ----------


func notify_building_damaged(building, attacker) -> void:
	# Called from Building.take_damage (physics tick — sim-state safe).
	# The rally point is the ATTACKER's position when known (defenders go
	# to the threat, not to the wound); falls back to the building.
	_last_base_damage_sim = GameState.sim_seconds()
	if attacker != null and is_instance_valid(attacker) and attacker is Node2D:
		_base_threat_pos = attacker.global_position
	elif building != null and is_instance_valid(building):
		_base_threat_pos = building.position


func sim_since_base_damage() -> float:
	return GameState.sim_seconds() - _last_base_damage_sim


func get_base_threat_pos() -> Vector2:
	return _base_threat_pos


# ---------- Strategist-facing API (production) ----------


func can_afford(cost: int) -> bool:
	return salvage >= cost


func is_producing() -> bool:
	return _producing


func has_barracks() -> bool:
	return _barracks != null and is_instance_valid(_barracks)


func has_tech_building() -> bool:
	return _tech_building != null and is_instance_valid(_tech_building)


# A4: first idle Shaman in our unit group (idle = its Sub state machine is
# NONE — not approaching, not channeling). First-seen on group order is the
# documented interim tie-break; matches typically field one Shaman.
func find_idle_shaman():
	for u in get_tree().get_nodes_in_group(_unit_group):
		if not is_instance_valid(u):
			continue
		if u.get_script() != SHAMAN_SCRIPT:
			continue
		if u.get("_sub") == 0:  # Shaman.Sub.NONE
			return u
	return null


# A5: the most exposed enemy WORKER — the opposing economy unit nearest
# OUR HQ. Workers stake out at infested buildings, so the nearest one is
# the loneliest. Strict min-distance, first-seen tie-break.
const LOOTER_SCRIPT_REF := preload("res://scripts/Looter.gd")
const WALKER_SCRIPT_REF := preload("res://scripts/Walker.gd")
const RUNNER_SCRIPT_REF := preload("res://scripts/SurvivorRunner.gd")


func find_exposed_enemy_worker():
	var enemy_group: String = "ai_units" if as_player_slot else "player_units"
	var hq_pos: Vector2 = get_hq_position()
	var best = null
	var best_dist: float = INF
	for u in get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(u):
			continue
		var s = u.get_script()
		if s != LOOTER_SCRIPT_REF and s != WALKER_SCRIPT_REF and s != RUNNER_SCRIPT_REF:
			continue
		if "current_hp" in u and u.current_hp <= 0:
			continue
		var d: float = hq_pos.distance_to(u.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best


# A4: force-spawn target — the infested Lootable nearest the ENEMY HQ
# (approved Decision C default). Strict min-distance, first-seen tie-break.
func find_forcespawn_target():
	var best = null
	var best_dist: float = INF
	for l in get_tree().get_nodes_in_group("lootable"):
		if not is_instance_valid(l):
			continue
		if not ("is_infested" in l) or not l.is_infested:
			continue
		var d: float = enemy_hq_position.distance_to(l.position)
		if d < best_dist:
			best_dist = d
			best = l
	return best


func spend_for_production(cost: int) -> bool:
	# H11: refuse spend after HQ death so the strategist's deferred bookkeeping
	# can't drain salvage into a production cycle that will never complete.
	if not is_alive():
		return false
	if salvage < cost:
		return false
	salvage -= cost
	return true


func start_production(item: String, time: float) -> void:
	if not is_alive():
		return
	_producing = true
	_producing_what = item
	_production_timer = time


func add_salvage(amount: int) -> void:
	salvage += amount


# ---------- Tactician-facing API (queries) ----------


func get_combat_units() -> Array:
	var arr: Array = []
	for u in get_tree().get_nodes_in_group(_unit_group):
		if not is_instance_valid(u):
			continue
		if u.is_in_group("combat_units"):
			arr.append(u)
	return arr


func get_combat_count() -> int:
	return get_combat_units().size()


# Counts living AI units whose script equals `script`. Used by AIStrategist's
# stall-recovery path (H2) to detect a dead economy without spawn-time bookkeeping.
func count_units_with_script(script) -> int:
	if script == null:
		return 0
	var n: int = 0
	for u in get_tree().get_nodes_in_group(_unit_group):
		if not is_instance_valid(u):
			continue
		if u.get_script() == script:
			n += 1
	return n


func get_hq_position() -> Vector2:
	if _hq != null and is_instance_valid(_hq):
		return _hq.position
	return spawn_position


func get_barracks_position() -> Vector2:
	if has_barracks():
		return _barracks.position
	return get_hq_position()


func get_enemy_hq_position() -> Vector2:
	return enemy_hq_position


# ---------- Internal: HQ and production ----------


func _spawn_hq() -> void:
	# A4: HQ routes by faction — same pattern Main._spawn_hq uses. The
	# TribalCamp doubles as the Tribal elimination condition (PLACEHOLDER
	# ruling — DESIGN_MASTER §12 #6 is still [OPEN]; Matt rules later).
	var scene: PackedScene = CP_SCENE
	if faction == GameState.Faction.TRIBAL:
		scene = TC_SCENE
	elif faction == GameState.Faction.SURVIVOR:
		scene = SH_SCENE
	_hq = scene.instantiate()
	_hq.position = spawn_position
	get_parent().add_child(_hq)
	_hq.add_to_group(_building_group)
	# A2: route damage events to this controller's SURVIVE posture.
	if "owner_controller" in _hq:
		_hq.owner_controller = self
	# Register with Main so its win-condition scan tracks our HQ. In AI-vs-AI
	# mode the "player slot" AI registers as the player HQ; the other side
	# registers as the opposing HQ - same plumbing the human-vs-AI mode uses.
	var main := get_parent()
	if main == null:
		return
	if as_player_slot:
		if main.has_method("set_player_hq"):
			main.set_player_hq(_hq)
	else:
		if main.has_method("set_opposing_hq"):
			main.set_opposing_hq(_hq)


func _tick_production(delta: float) -> void:
	if not _producing:
		return
	# H11: if the HQ went down mid-production, cancel cleanly. _spawn_produced
	# reads _hq.position for spawn anchors and would crash on a freed node.
	if not is_alive():
		_producing = false
		_producing_what = ""
		_production_timer = 0.0
		return
	_production_timer -= delta
	if _production_timer > 0:
		return
	_spawn_produced(_producing_what)
	_producing = false
	_producing_what = ""


func _spawn_produced(item: String) -> void:
	match item:
		"looter":
			_spawn_unit(LOOTER_SCENE, _hq.position + LOOTER_SPAWN_OFFSET)
		"walker":
			_spawn_unit(WALKER_SCENE, _hq.position + LOOTER_SPAWN_OFFSET)
		"rifleman":
			var origin: Vector2 = _barracks.position if has_barracks() else _hq.position
			_spawn_unit(RIFLEMAN_SCENE, origin + RIFLEMAN_SPAWN_OFFSET)
		"heavy_gunner":
			var origin2: Vector2 = _barracks.position if has_barracks() else _hq.position
			_spawn_unit(HEAVY_GUNNER_SCENE, origin2 + RIFLEMAN_SPAWN_OFFSET)
		"hunter":
			var origin3: Vector2 = _barracks.position if has_barracks() else _hq.position
			_spawn_unit(HUNTER_SCENE, origin3 + RIFLEMAN_SPAWN_OFFSET)
		"shaman":
			var origin4: Vector2 = _tech_building.position if has_tech_building() else _hq.position
			_spawn_unit(SHAMAN_SCENE, origin4 + RIFLEMAN_SPAWN_OFFSET)
		"barracks":
			_barracks = _spawn_structure(BARRACKS_SCENE, _hq.position + BARRACKS_SPAWN_OFFSET)
		"hunting_lodge":
			_barracks = _spawn_structure(HUNTING_LODGE_SCENE, _hq.position + BARRACKS_SPAWN_OFFSET)
		"ritual_site":
			_tech_building = _spawn_structure(RITUAL_SITE_SCENE, _hq.position + TECH_SPAWN_OFFSET)
		# Survivor roster (2026-06-11): the HQ produces every unit, so all
		# spawn at the HQ. Farm east, radio west — 280px apart, inside the
		# radio's 320px farm-attach radius, so the broadcast income arm
		# comes online the moment both stand.
		"runner":
			_spawn_unit(SURVIVOR_RUNNER_SCENE, _hq.position + LOOTER_SPAWN_OFFSET)
		"bolter":
			_spawn_unit(BOLTER_SCENE, _hq.position + RIFLEMAN_SPAWN_OFFSET)
		"brawler":
			_spawn_unit(BRAWLER_SCENE, _hq.position + RIFLEMAN_SPAWN_OFFSET)
		"chemist":
			_spawn_unit(CHEMIST_SCENE, _hq.position + RIFLEMAN_SPAWN_OFFSET)
		"farm":
			_spawn_structure(FARM_SCENE, _hq.position + BARRACKS_SPAWN_OFFSET)
		"radio_station":
			_spawn_structure(RADIO_SCENE, _hq.position + TECH_SPAWN_OFFSET)


# A4: shared structure spawn — ownership tag, A2 damage routing, nav rebake.
func _spawn_structure(scene: PackedScene, pos: Vector2) -> Node2D:
	var b: Node2D = scene.instantiate()
	b.position = pos
	get_parent().add_child(b)
	b.add_to_group(_building_group)
	if "owner_controller" in b:
		b.owner_controller = self
	if get_parent().has_method("rebake_navigation"):
		get_parent().call_deferred("rebake_navigation")
	return b


const SPAWN_JITTER := 24.0
# A3/A4: how far from the HQ the AI is willing to stake a Looter onto an
# infested building. The original 14 tiles found ZERO infested buildings
# near some spawn corners (seed-42 player corner among them), which
# silently zeroed the player-slot AI's income in every lab run — Military
# income IS zombie farming, so no infested in range = structurally dead
# economy. 40 tiles trades commute time for a guaranteed income source.
const LOOTER_STAKE_RADIUS_PX := 40.0 * 32.0

# A4: round-robin cursor so successive Looters stake DIFFERENT infested
# buildings instead of stacking on one spawner.
var _stake_counter: int = 0


func _find_looter_stake() -> Vector2:
	# i-th nearest infested Lootable to the HQ within stake range, where i
	# cycles per Looter staked. Deterministic: sorted by (distance, x, y).
	var hq_pos: Vector2 = get_hq_position()
	var candidates: Array = []
	for l in get_tree().get_nodes_in_group("lootable"):
		if not is_instance_valid(l):
			continue
		if not ("is_infested" in l) or not l.is_infested:
			continue
		var d: float = hq_pos.distance_to(l.position)
		if d < LOOTER_STAKE_RADIUS_PX:
			candidates.append([d, l.position.x, l.position.y])
	if candidates.is_empty():
		return Vector2.ZERO
	candidates.sort()
	var pick: Array = candidates[_stake_counter % candidates.size()]
	_stake_counter += 1
	return Vector2(pick[1], pick[2])


func _spawn_unit(scene: PackedScene, pos: Vector2) -> void:
	if scene == null:
		return
	var u = scene.instantiate()
	# Jitter prevents stacked spawns from being separated in arbitrary
	# directions by the physics solver (the "ran left off the screen" bug).
	# SimRng (D8/CI 2026-06-09): AI spawn positions are sim state.
	var jitter := Vector2(SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), SimRng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	u.position = pos + jitter
	get_parent().add_child(u)
	# After add_child the unit's scene-defined groups have applied. Flip
	# ownership to the right side: the "ai slot" AI re-tags spawned units
	# from player_units -> ai_units; the "player slot" AI leaves them in
	# player_units (the scene default), so SelectionManager will let the
	# human watch them but won't deflect ownership/hostility logic.
	if not as_player_slot:
		u.remove_from_group("player_units")
		u.add_to_group("ai_units")
	# Bind the unit to this controller for salvage routing. Without this,
	# Looter._deposit_at_home falls back to GameState (or to the wrong
	# AIController under AI-vs-AI's get_first_node_in_group lookup) and the
	# controller's pool starves.
	if "owner_controller" in u:
		u.owner_controller = self
	# A3: work-anchor staking — the Military identity play. New Looters get
	# anchored at the nearest infested Lootable within range of the HQ, so
	# the AI farms the spawns its own noise feeds instead of leaving every
	# Looter parked on the doorstep. Deterministic: strict min-distance,
	# first-seen tie-break.
	if u.has_method("set_work_anchor"):
		var stake: Vector2 = _find_looter_stake()
		if stake != Vector2.ZERO:
			u.set_work_anchor(stake)
