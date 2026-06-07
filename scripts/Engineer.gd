extends "res://scripts/Unit.gd"

enum Sub { NONE, REPAIR_APPROACH, REPAIR_CHANNEL, CONSTRUCTING, FLEE }

const ATTACK_RANGE := 36.0
const ATTACK_DAMAGE := 8
const ATTACK_PERIOD := 1.0
const ENGAGE_RANGE := 160.0
const REPAIR_RANGE := 80.0
const REPAIR_HP_PER_SEC := 5.0
const FLEE_HP_FRACTION := 0.5
const FLEE_THREAT_RANGE := 200.0
const RETARGET_INTERVAL := 0.3
const CONSTRUCTION_SPAWN_OFFSET := Vector2(80, 0)
const WALL_SCENE_PATH := "res://scenes/buildings/Wall.tscn"
const WALL_ARRIVE_RANGE := 56.0

const BUILDABLE_ORDER := ["workshop", "safehouse", "greenhouse", "water_collection", "wall"]
const BUILDABLE_COSTS := { "workshop": 150, "safehouse": 150, "greenhouse": 100, "water_collection": 75, "wall": 25 }
const BUILDABLE_TIMES := { "workshop": 40.0, "safehouse": 50.0, "greenhouse": 30.0, "water_collection": 25.0, "wall": 10.0 }
const BUILDABLE_PATHS := {
	"workshop": "res://scenes/buildings/Workshop.tscn",
	"safehouse": "res://scenes/buildings/Safehouse.tscn",
	"greenhouse": "res://scenes/buildings/Greenhouse.tscn",
	"water_collection": "res://scenes/buildings/WaterCollection.tscn",
}

var _target_enemy = null
var _repair_target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
var _sub: Sub = Sub.NONE
var _repair_accumulator := 0.0
var _construction_what := ""
var _construction_timer := 0.0
var _building_wall := false
var _wall_target: Vector2 = Vector2.ZERO


func repair_at(building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not ("current_hp" in building) or not ("max_hp" in building):
		return
	if building.current_hp >= building.max_hp:
		return
	_repair_target = building
	_sub = Sub.REPAIR_APPROACH
	current_command = Command.CONSTRUCT
	_nav.target_position = building.position


func build_wall_at(pos: Vector2) -> void:
	_building_wall = true
	_wall_target = pos
	_construction_what = "wall"
	_construction_timer = BUILDABLE_TIMES["wall"]
	_sub = Sub.CONSTRUCTING
	current_command = Command.CONSTRUCT
	_nav.target_position = pos


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	if _sub != Sub.CONSTRUCTING:
		_sub = Sub.NONE
		_repair_target = null


func get_action_count() -> int:
	return BUILDABLE_ORDER.size()


func get_action_text(idx: int) -> String:
	if idx < 0 or idx >= BUILDABLE_ORDER.size():
		return ""
	var item: String = BUILDABLE_ORDER[idx]
	return "Build %s (%d Salvage)" % [_pretty_name(item), BUILDABLE_COSTS[item]]


func _pretty_name(item: String) -> String:
	match item:
		"workshop": return "Workshop"
		"safehouse": return "Safehouse"
		"greenhouse": return "Greenhouse"
		"water_collection": return "Water Collection"
		"wall": return "Wall"
		_: return item.capitalize()


func get_action_available(idx: int) -> bool:
	if _sub == Sub.CONSTRUCTING:
		return false
	if idx < 0 or idx >= BUILDABLE_ORDER.size():
		return false
	return GameState.can_spend(BUILDABLE_COSTS[BUILDABLE_ORDER[idx]])


func do_action(idx: int) -> void:
	if _sub == Sub.CONSTRUCTING:
		return
	if idx < 0 or idx >= BUILDABLE_ORDER.size():
		return
	var item: String = BUILDABLE_ORDER[idx]
	if item == "wall":
		# Walls go through placement mode; cost is paid on placement confirm.
		var sel = get_tree().get_first_node_in_group("selection_manager")
		if sel != null and sel.has_method("start_wall_placement"):
			sel.start_wall_placement(self)
		return
	if not GameState.can_spend(BUILDABLE_COSTS[item]):
		return
	GameState.spend(BUILDABLE_COSTS[item])
	_start_construction(item)


func get_status_text() -> String:
	if _sub == Sub.CONSTRUCTING:
		return "Constructing %s... %.0fs" % [_pretty_name(_construction_what), _construction_timer]
	return ""


func _start_construction(item: String) -> void:
	_building_wall = false
	_construction_what = item
	_construction_timer = BUILDABLE_TIMES[item]
	_sub = Sub.CONSTRUCTING
	current_command = Command.CONSTRUCT


func _spawn_construction() -> void:
	if _building_wall:
		var wall_scene: PackedScene = load(WALL_SCENE_PATH) as PackedScene
		if wall_scene != null:
			var w = wall_scene.instantiate()
			w.position = _wall_target
			get_parent().add_child(w)
			# H10 ownership tagging - Engineer is a player-only unit (no AI
			# Survivor), so spawned walls and buildings are player-owned.
			w.add_to_group("player_buildings")
		_building_wall = false
	else:
		var path: String = BUILDABLE_PATHS.get(_construction_what, "")
		if path != "":
			var scene: PackedScene = load(path) as PackedScene
			if scene != null:
				var b = scene.instantiate()
				b.position = global_position + CONSTRUCTION_SPAWN_OFFSET
				get_parent().add_child(b)
				b.add_to_group("player_buildings")
				_request_nav_rebake()
	_construction_what = ""
	_sub = Sub.NONE
	current_command = Command.IDLE


func _request_nav_rebake() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)

	var max_eff: int = get_effective_max_hp()
	var low_hp: bool = max_eff > 0 and float(current_hp) / float(max_eff) < FLEE_HP_FRACTION
	if low_hp and _sub != Sub.CONSTRUCTING:
		var threat = _find_nearest_hostile_in_range(FLEE_THREAT_RANGE)
		if threat != null:
			_sub = Sub.FLEE
			_flee_from(threat)
			return
		elif _sub == Sub.FLEE:
			_sub = Sub.NONE

	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	match _sub:
		Sub.REPAIR_APPROACH:
			_tick_repair_approach()
		Sub.REPAIR_CHANNEL:
			_tick_repair_channel(delta)
		Sub.CONSTRUCTING:
			_tick_constructing(delta)
		_:
			_tick_combat(delta)


func _tick_combat(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target_enemy = _find_nearest_hostile_in_range(ENGAGE_RANGE)

	if _target_enemy == null or not is_instance_valid(_target_enemy):
		velocity = Vector2.ZERO
		return

	var dist := global_position.distance_to(_target_enemy.global_position)
	if dist <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if _attack_cooldown <= 0:
			_target_enemy.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
			_attack_cooldown = ATTACK_PERIOD
	else:
		_nav.target_position = _target_enemy.global_position
		_follow_navigation()


func _tick_repair_approach() -> void:
	if _repair_target == null or not is_instance_valid(_repair_target):
		_sub = Sub.NONE
		current_command = Command.IDLE
		return
	if global_position.distance_to(_repair_target.position) <= REPAIR_RANGE:
		_sub = Sub.REPAIR_CHANNEL
		velocity = Vector2.ZERO
	else:
		_follow_navigation()


func _tick_repair_channel(delta: float) -> void:
	velocity = Vector2.ZERO
	if _repair_target == null or not is_instance_valid(_repair_target):
		_sub = Sub.NONE
		current_command = Command.IDLE
		return
	if _repair_target.current_hp >= _repair_target.max_hp:
		_sub = Sub.NONE
		current_command = Command.IDLE
		return
	_repair_accumulator += REPAIR_HP_PER_SEC * delta
	if _repair_accumulator >= 1.0:
		var heal: int = int(_repair_accumulator)
		_repair_accumulator -= float(heal)
		_repair_target.current_hp = min(_repair_target.max_hp, _repair_target.current_hp + heal)
		if _repair_target.has_method("queue_redraw"):
			_repair_target.queue_redraw()


func _tick_constructing(delta: float) -> void:
	if _building_wall:
		if global_position.distance_to(_wall_target) > WALL_ARRIVE_RANGE:
			_follow_navigation()
			return
		velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	_construction_timer -= delta
	if _construction_timer <= 0.0:
		_spawn_construction()


func _flee_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * get_effective_move_speed()
	move_and_slide()


func _find_nearest_hostile_in_range(range_px: float):
	# Hostility routed through GameState.is_hostile (AUDIT H4) - team-based,
	# so an opposite-team Survivor mirror would correctly identify threats.
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best
