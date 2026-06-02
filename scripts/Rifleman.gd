extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 213.0
const ATTACK_DAMAGE := 12
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 10.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

# Projectile config: small yellow bullet. Speed is 2x the firer's move_speed
# (computed at fire time) so each bullet visibly outpaces the shooter but
# stays slow enough to track. Rifleman at 80 move_speed -> 160 px/s bullets.
const PROJECTILE_COLOR := Color(0.95, 0.78, 0.35)
# Base accuracy in degrees. Lower = tighter cone. Squad accuracy bonus (from
# leadership aura) reduces effective spread multiplicatively:
# effective_spread = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus).
const BASE_ACCURACY_DEG := 4.0

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		elif stance == Stance.AGGRESSIVE:
			_try_shoot_in_range(delta)
		return

	if stance == Stance.PASSIVE:
		velocity = Vector2.ZERO
		return

	var threat = _find_nearest_threat_in_range(KITE_RANGE)
	if threat != null:
		_kite_from(threat)
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise()


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: keep the nav target, but fire opportunistically at
	# anything in ATTACK_RANGE. No kiting (we honor the move order). Reuses the
	# same cooldown/retarget cadence as the idle attack path.
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD
		_emit_shot_noise()


func _fire_at(target) -> void:
	# Spawns a direct-fire projectile. Damage resolves on impact, not here.
	# Noise still fires at the call site (fire-time, per the projectile spec).
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus)
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": move_speed * 2.0,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 6.0,  # bullet radius in px - large for visibility test
	})


func _find_nearest_zombie():
	# Despite the legacy name, this targets ANY hostile - any unit not of our own
	# faction or Neutral. Lets AI Military shoot player Tribal/Survivor (and the
	# reverse if the player picks Military without AI on). If no hostile unit is
	# in range, falls back to the nearest opposing HQ so units posted at the enemy
	# base auto-attack the HQ for the win condition.
	var best = null
	var best_dist := ATTACK_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == faction or u.faction == GameState.Faction.NEUTRAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(ATTACK_RANGE)


func _find_nearest_hostile_hq(range_px: float):
	# Opposing HQ = HQ tagged with the ownership group opposite to ours.
	var enemy_group: String = "player_buildings" if is_in_group("ai_units") else "ai_buildings"
	var best = null
	var best_dist := range_px
	for b in get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(b):
			continue
		if not b.is_in_group("hq"):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d <= best_dist:
			best_dist = d
			best = b
	return best


func _find_nearest_threat_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == faction or u.faction == GameState.Faction.NEUTRAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d <= best_dist:
			best_dist = d
			best = c
	return best


func _kite_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * KITE_SPEED
	move_and_slide()


func _emit_shot_noise() -> void:
	NoiseBus.emit(global_position, NOISE_PER_SHOT)
