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

var salvage: int = 200
var strategist: AIStrategist
var tactician: AITactician

var _strategic_timer: float = 0.0
var _tactical_timer: float = 0.0
var _hq: Node2D = null
var _barracks: Node2D = null

var _producing: bool = false
var _producing_what: String = ""
var _production_timer: float = 0.0


func _ready() -> void:
	add_to_group("ai_controller")
	strategist = AIStrategist.new()
	strategist.controller = self
	tactician = AITactician.new()
	tactician.controller = self
	_spawn_hq()


func _process(delta: float) -> void:
	_tick_production(delta)

	_strategic_timer += delta
	if _strategic_timer >= STRATEGIC_INTERVAL:
		_strategic_timer = 0.0
		strategist.evaluate()

	_tactical_timer += delta
	if _tactical_timer >= TACTICAL_INTERVAL:
		_tactical_timer = 0.0
		tactician.evaluate()


# ---------- Strategist-facing API (production) ----------


func can_afford(cost: int) -> bool:
	return salvage >= cost


func is_producing() -> bool:
	return _producing


func has_barracks() -> bool:
	return _barracks != null and is_instance_valid(_barracks)


func spend_for_production(cost: int) -> bool:
	if salvage < cost:
		return false
	salvage -= cost
	return true


func start_production(item: String, time: float) -> void:
	_producing = true
	_producing_what = item
	_production_timer = time


func add_salvage(amount: int) -> void:
	salvage += amount


# ---------- Tactician-facing API (queries) ----------


func get_combat_units() -> Array:
	var arr: Array = []
	for u in get_tree().get_nodes_in_group("ai_units"):
		if not is_instance_valid(u):
			continue
		if u.is_in_group("combat_units"):
			arr.append(u)
	return arr


func get_combat_count() -> int:
	return get_combat_units().size()


func get_hq_position() -> Vector2:
	if _hq != null and is_instance_valid(_hq):
		return _hq.position
	return spawn_position


func get_enemy_hq_position() -> Vector2:
	return enemy_hq_position


# ---------- Internal: HQ and production ----------


func _spawn_hq() -> void:
	_hq = CP_SCENE.instantiate()
	_hq.position = spawn_position
	get_parent().add_child(_hq)
	_hq.add_to_group("ai_buildings")


func _tick_production(delta: float) -> void:
	if not _producing:
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
			_barracks.add_to_group("ai_buildings")
			if get_parent().has_method("rebake_navigation"):
				get_parent().call_deferred("rebake_navigation")


func _spawn_unit(scene: PackedScene, pos: Vector2) -> void:
	if scene == null:
		return
	var u = scene.instantiate()
	u.position = pos
	get_parent().add_child(u)
	# After add_child the unit's scene-defined groups have applied; flip ownership
	# so SelectionManager won't let the player command it and Looter deposits route
	# to the AI's salvage pool.
	u.remove_from_group("player_units")
	u.add_to_group("ai_units")
