extends "res://scripts/Unit.gd"

enum Sub { NONE, REPAIR_APPROACH, REPAIR_CHANNEL, FLEE }

const ATTACK_RANGE := 36.0
const ATTACK_DAMAGE := 8
const ATTACK_PERIOD := 1.0
const ENGAGE_RANGE := 160.0
const REPAIR_RANGE := 80.0
const REPAIR_HP_PER_SEC := 5.0
const FLEE_HP_FRACTION := 0.5
const FLEE_THREAT_RANGE := 200.0
const RETARGET_INTERVAL := 0.3

var _target_enemy = null
var _repair_target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
var _sub: Sub = Sub.NONE
var _repair_accumulator := 0.0


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


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_sub = Sub.NONE
	_repair_target = null


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)

	var max_eff: int = get_effective_max_hp()
	var low_hp: bool = max_eff > 0 and float(current_hp) / float(max_eff) < FLEE_HP_FRACTION
	if low_hp:
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


func _flee_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * get_effective_move_speed()
	move_and_slide()


func _find_nearest_hostile_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == Faction.SURVIVOR or u.faction == Faction.NEUTRAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best
