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
var _barracks: Node2D = null

var _producing: bool = false
var _producing_what: String = ""
var _production_timer: float = 0.0

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
	MatchStats.log_event(&"ai_phase", {
		"controller": get_controller_id(),
		"step": strategist.get_step() if strategist != null else -1,
		"state": strategist.get_state_name() if strategist != null else "UNKNOWN",
		"salvage": salvage,
		"looters": count_units_with_script(LOOTER_SCRIPT),
		"combat": get_combat_count(),
		"has_barracks": has_barracks(),
	})


# ---------- Strategist-facing API (production) ----------


func can_afford(cost: int) -> bool:
	return salvage >= cost


func is_producing() -> bool:
	return _producing


func has_barracks() -> bool:
	return _barracks != null and is_instance_valid(_barracks)


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
	_hq = CP_SCENE.instantiate()
	_hq.position = spawn_position
	get_parent().add_child(_hq)
	_hq.add_to_group(_building_group)
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
		"rifleman":
			var origin: Vector2 = _barracks.position if has_barracks() else _hq.position
			_spawn_unit(RIFLEMAN_SCENE, origin + RIFLEMAN_SPAWN_OFFSET)
		"heavy_gunner":
			var origin2: Vector2 = _barracks.position if has_barracks() else _hq.position
			_spawn_unit(HEAVY_GUNNER_SCENE, origin2 + RIFLEMAN_SPAWN_OFFSET)
		"barracks":
			_barracks = BARRACKS_SCENE.instantiate()
			_barracks.position = _hq.position + BARRACKS_SPAWN_OFFSET
			get_parent().add_child(_barracks)
			_barracks.add_to_group(_building_group)
			if get_parent().has_method("rebake_navigation"):
				get_parent().call_deferred("rebake_navigation")


const SPAWN_JITTER := 24.0


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
