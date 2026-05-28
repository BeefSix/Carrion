extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 36.0
const ATTACK_DAMAGE := 22
const ATTACK_PERIOD := 1.0
const NOISE_PER_HIT := 0.0
const ENGAGE_RANGE := 200.0
const RETARGET_INTERVAL := 0.3

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile()

	if _target == null or not is_instance_valid(_target):
		velocity = Vector2.ZERO
		return

	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if _attack_cooldown <= 0:
			_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
			_attack_cooldown = ATTACK_PERIOD
	else:
		_nav.target_position = _target.global_position
		_follow_navigation()


# Survivor Brawler engages anything that isn't a Survivor or neutral - zombies,
# military, tribal all trigger combat. Melee silent (NOISE_PER_HIT = 0).
func _find_nearest_hostile():
	var best = null
	var best_dist := ENGAGE_RANGE
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
