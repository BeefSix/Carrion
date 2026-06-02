class_name Looter
extends "res://scripts/Unit.gd"

enum Sub {
	NONE,
	HUNT_APPROACH,
	HUNT_FIRE,
	RETURN_HOME,
	RETURN_TO_HUNT,
	SEARCH,
	PATROL,
}

const MAGNUM_DAMAGE := 22
const MAGNUM_PERIOD := 2.5
const MAGNUM_RANGE := 128.0
const MAGNUM_NOISE := 20.0

# Projectile config: heavier brass-toned bullet to read as a magnum round.
# Speed is 2x move_speed (set at fire time). Looter at 96 -> 192 px/s.
const PROJECTILE_COLOR := Color(0.92, 0.66, 0.30)
const BASE_ACCURACY_DEG := 5.0  # mid-range between Rifleman (4) and HG (8)
const HUNT_VISION := 384.0
const SALVAGE_PER_KILL := 25
const CARRY_CAP := 25
const INTERACTION_RANGE := 80.0
const KILL_AREA_ARRIVE_RANGE := 80.0
const RETARGET_INTERVAL := 0.3
const SEARCH_DURATION := 6.0
const SEARCH_RADIUS := 150.0
const SEARCH_WANDER_INTERVAL := 1.5

# Carrying-loot avoidance: when a zombie is within AVOID_RANGE on the return
# trip, retarget the nav agent to a sidestep waypoint instead of straight
# home. The sidestep is computed from a perpendicular-to-threat offset blended
# with the home direction, so the Looter routes around the zombie via the
# nav mesh (not raw velocity steering - that was the original "sprinting
# off the map" bug). Restored from spec §4.1 per the design doc.
const AVOID_RANGE := 160.0
const AVOID_DETOUR_PX := 120.0
const AVOID_RETARGET_INTERVAL := 0.5

# Patrol behavior: when a Looter spawns with no kill memory and no zombie
# in immediate vision, they pick small random offsets and walk to scan
# new ground rather than standing still. Each leg is short so they cover
# territory gradually and stay re-routable when zombies appear.
const PATROL_RADIUS_MIN := 150.0
const PATROL_RADIUS_MAX := 350.0
const PATROL_SCAN_INTERVAL := 0.5
const PATROL_ARRIVE_RANGE := 48.0

var _sub: Sub = Sub.NONE
var _target_zombie = null
var _home_base = null
var _carrying := 0
var _attack_cooldown := 0.0
var _retarget_timer := 0.0

# _has_kill is the sentinel for "this Looter has killed something this match
# and knows where to go hunt again." Previously we keyed on _last_kill_pos
# being non-zero, which broke the moment a kill happened to land on (0, 0)
# and was just a code smell otherwise.
var _has_kill: bool = false
var _last_kill_pos: Vector2 = Vector2.ZERO
var _search_timer := 0.0
var _search_wander_timer := 0.0

# Throttle to avoid hammering _nav.target_position every frame on the return
# trip; the nav agent re-paths whenever the target changes.
var _avoid_retarget_timer: float = 0.0

var _patrol_target: Vector2 = Vector2.ZERO
var _patrol_scan_timer: float = 0.0

# Salvage award on kill credit. Damage now resolves at projectile-impact time,
# not at fire time, so we can't check "did the zombie die from this shot?"
# inline. Instead we watch kills_count for an increment and award salvage on
# the delta. Kills only credit when the target actually dies (per Unit base).
var _last_kills_count: int = 0


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	# Preserve _last_kill_pos so the cycle resumes after the manual detour.
	_sub = Sub.NONE
	_target_zombie = null


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer = max(0.0, _retarget_timer - delta)

	# Projectile-delayed kill detection. If kills_count incremented since last
	# tick, a projectile we fired landed and killed something. Award salvage
	# and transition to return-home, the same state changes the old inline
	# damage path produced at fire-time.
	if kills_count > _last_kills_count:
		var new_kills: int = kills_count - _last_kills_count
		_last_kills_count = kills_count
		_carrying = min(_carrying + new_kills * SALVAGE_PER_KILL, CARRY_CAP)
		_last_kill_pos = global_position
		_has_kill = true
		_target_zombie = null
		_start_return_home()

	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		_pick_next_action()

	match _sub:
		Sub.HUNT_APPROACH:
			_tick_hunt_approach()
		Sub.HUNT_FIRE:
			_tick_hunt_fire()
		Sub.RETURN_HOME:
			_tick_return_home()
		Sub.RETURN_TO_HUNT:
			_tick_return_to_hunt()
		Sub.SEARCH:
			_tick_search(delta)
		Sub.PATROL:
			_tick_patrol(delta)
		_:
			velocity = Vector2.ZERO


func _pick_next_action() -> void:
	if _carrying > 0:
		_start_return_home()
		return
	if _has_kill:
		_start_return_to_hunt()
		return
	_try_start_auto_hunt()


func _try_start_auto_hunt() -> void:
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z == null:
		# Nothing in vision - start patrolling small offsets to scan more
		# ground instead of standing still until a zombie wanders by.
		_start_patrol()
		return
	_target_zombie = z
	_sub = Sub.HUNT_APPROACH
	_nav.target_position = z.global_position


func _start_patrol() -> void:
	var angle: float = randf() * TAU
	var dist: float = randf_range(PATROL_RADIUS_MIN, PATROL_RADIUS_MAX)
	var target: Vector2 = global_position + Vector2.from_angle(angle) * dist
	target.x = clamp(target.x, 50.0, 6094.0)
	target.y = clamp(target.y, 50.0, 6094.0)
	_patrol_target = target
	_patrol_scan_timer = 0.0
	_sub = Sub.PATROL
	_nav.target_position = _patrol_target


func _tick_patrol(delta: float) -> void:
	# Scan for zombies on the way - if one comes into vision, switch to
	# hunt immediately. Patrol is just to find new ground; the moment
	# there's a target the patrol is over.
	_patrol_scan_timer -= delta
	if _patrol_scan_timer <= 0.0:
		_patrol_scan_timer = PATROL_SCAN_INTERVAL
		var z = _find_nearest_zombie_in_range(HUNT_VISION)
		if z != null:
			_target_zombie = z
			_sub = Sub.HUNT_APPROACH
			_nav.target_position = z.global_position
			return
	# Arrived or nav stuck - pick a fresh patrol leg.
	if global_position.distance_to(_patrol_target) <= PATROL_ARRIVE_RANGE or _nav.is_navigation_finished():
		_start_patrol()
		return
	_follow_navigation()


func _start_return_home() -> void:
	_home_base = _find_nearest_command_post()
	if _home_base == null:
		velocity = Vector2.ZERO
		return
	_sub = Sub.RETURN_HOME
	_nav.target_position = _home_base.position


func _start_return_to_hunt() -> void:
	if global_position.distance_to(_last_kill_pos) <= KILL_AREA_ARRIVE_RANGE:
		_enter_search()
		return
	_sub = Sub.RETURN_TO_HUNT
	_nav.target_position = _last_kill_pos


func _enter_search() -> void:
	_sub = Sub.SEARCH
	_search_timer = SEARCH_DURATION
	_search_wander_timer = 0.0


func _tick_hunt_approach() -> void:
	if _target_zombie == null or not is_instance_valid(_target_zombie):
		_sub = Sub.NONE
		return
	var dist := global_position.distance_to(_target_zombie.global_position)
	if dist <= MAGNUM_RANGE:
		_sub = Sub.HUNT_FIRE
		velocity = Vector2.ZERO
		return
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_nav.target_position = _target_zombie.global_position
	_follow_navigation()


func _tick_hunt_fire() -> void:
	if _target_zombie == null or not is_instance_valid(_target_zombie):
		_sub = Sub.NONE
		return
	velocity = Vector2.ZERO
	var dist := global_position.distance_to(_target_zombie.global_position)
	if dist > MAGNUM_RANGE * 1.2:
		_sub = Sub.HUNT_APPROACH
		return
	if _attack_cooldown <= 0.0:
		_attack_cooldown = MAGNUM_PERIOD
		_emit_magnum_noise()
		# Damage now resolves at projectile-impact time. The kills_count delta
		# check at the top of _physics_process picks up the kill credit and
		# triggers the return-home transition.
		_fire_at(_target_zombie)


func _fire_at(target) -> void:
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus)
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(MAGNUM_DAMAGE)),
		"speed": move_speed * 2.0,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 6.5,  # bullet radius in px - large for visibility test
	})


func _tick_return_home() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_command_post()
		if _home_base == null:
			_sub = Sub.NONE
			velocity = Vector2.ZERO
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		_deposit_at_home()
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	# Defensive fire is no-velocity (just damage + noise), so we can shoot while
	# walking.
	_try_defensive_fire()
	# Zombie-shy detour: if a zombie is within AVOID_RANGE, retarget the nav
	# agent to a sidestep waypoint (perpendicular-from-threat blended with
	# home direction) so the path routes around it via the nav mesh. Throttled
	# so we don't re-path every frame.
	_avoid_retarget_timer -= get_physics_process_delta_time()
	if _avoid_retarget_timer <= 0.0:
		_avoid_retarget_timer = AVOID_RETARGET_INTERVAL
		var threat = _find_nearest_zombie_in_range(AVOID_RANGE)
		if threat != null:
			var away: Vector2 = (global_position - threat.global_position).normalized()
			var to_home: Vector2 = (_home_base.position - global_position).normalized()
			var sidestep: Vector2 = global_position + away * AVOID_DETOUR_PX + to_home * AVOID_DETOUR_PX
			sidestep.x = clamp(sidestep.x, 50.0, 6094.0)
			sidestep.y = clamp(sidestep.y, 50.0, 6094.0)
			_nav.target_position = sidestep
		else:
			# No threat - direct line home.
			_nav.target_position = _home_base.position
	_follow_navigation()


func _try_defensive_fire() -> void:
	if _attack_cooldown > 0.0:
		return
	var z = _find_nearest_zombie_in_range(MAGNUM_RANGE)
	if z == null:
		return
	_attack_cooldown = MAGNUM_PERIOD
	_emit_magnum_noise()
	# Defensive kills don't increase carry — already at cap.
	z.take_damage(get_effective_damage(MAGNUM_DAMAGE), self)


func _tick_return_to_hunt() -> void:
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z != null:
		_target_zombie = z
		_sub = Sub.HUNT_APPROACH
		_nav.target_position = z.global_position
		return
	if global_position.distance_to(_last_kill_pos) <= KILL_AREA_ARRIVE_RANGE:
		_enter_search()
		return
	_follow_navigation()


func _tick_search(delta: float) -> void:
	_search_timer -= delta
	var z = _find_nearest_zombie_in_range(HUNT_VISION)
	if z != null:
		_target_zombie = z
		_sub = Sub.HUNT_APPROACH
		_nav.target_position = z.global_position
		return
	if _search_timer <= 0.0:
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_search_wander_timer -= delta
	if _search_wander_timer <= 0.0:
		_search_wander_timer = SEARCH_WANDER_INTERVAL
		var offset := Vector2(randf_range(-SEARCH_RADIUS, SEARCH_RADIUS), randf_range(-SEARCH_RADIUS, SEARCH_RADIUS))
		var t: Vector2 = _last_kill_pos + offset
		t.x = clamp(t.x, 50.0, 6094.0)
		t.y = clamp(t.y, 50.0, 6094.0)
		_nav.target_position = t
	if not _nav.is_navigation_finished():
		_follow_navigation()
	else:
		velocity = Vector2.ZERO


func _deposit_at_home() -> void:
	if _carrying > 0:
		if is_in_group("ai_units"):
			var ai = get_tree().get_first_node_in_group("ai_controller")
			if ai != null and ai.has_method("add_salvage"):
				ai.add_salvage(_carrying)
		else:
			GameState.add_salvage(_carrying)
	_carrying = 0


func _find_nearest_zombie_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction != GameState.Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _find_nearest_command_post():
	# Prefer an owned CP - same-ownership group ("player_buildings" if the player
	# spawned us, "ai_buildings" if the AI spawned us). Falls back to any CP only
	# if our owned HQ is gone, in which case we'll just idle at whatever's left.
	var owner_group: String = "ai_buildings" if is_in_group("ai_units") else "player_buildings"
	var nearest = null
	var nearest_dist := INF
	for cp in get_tree().get_nodes_in_group("command_post"):
		if not is_instance_valid(cp):
			continue
		if not cp.is_in_group(owner_group):
			continue
		var dist: float = global_position.distance_to(cp.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cp
	if nearest != null:
		return nearest
	# Fallback: any CP, just so we don't go null and lock up.
	for cp in get_tree().get_nodes_in_group("command_post"):
		if not is_instance_valid(cp):
			continue
		var dist: float = global_position.distance_to(cp.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cp
	return nearest


func _emit_magnum_noise() -> void:
	NoiseBus.emit(global_position, MAGNUM_NOISE)
