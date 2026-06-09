class_name Looter
extends "res://scripts/CombatUnit.gd"

# Sub-state machine (territorial farmer redesign 2026-06-08; DESIGN_MASTER §7.1):
#   NONE          - idle at work anchor, will reconsider next tick
#   HUNT_APPROACH - walking toward a zombie inside the leash zone
#   HUNT_FIRE     - in magnum range, firing + back-away kite
#   RETURN_HOME   - carrying scrap, fast-running to the home CP to deposit
#   PATROL        - slow walk back to the work anchor when no target is in zone
# (Previous RETURN_TO_HUNT / SEARCH states are gone with the kill-memory
# loop they served - the work-anchor is the canonical "where I work" now.)
enum Sub {
	NONE,
	HUNT_APPROACH,
	HUNT_FIRE,
	RETURN_HOME,
	PATROL,
}

# Magnum tuning (2026-06-08 feel pass, PLACEHOLDERS for the balance lab).
# Damage = 42 one-shots a base 40-HP Shambler (clean_kill = no corpse,
# preserving the headshot-trained identity). HP in the scene file sits at
# 45 so a Looter survives 3 Shambler bites (14 dmg each = 42) and dies on
# the 4th - a fragile farmer with a definite "leave by hit #3" window.
# Period stays slow (anti-rush), range stays mid (anti-rush), no AOE.
const MAGNUM_DAMAGE := 42
const MAGNUM_PERIOD := 2.5
const MAGNUM_RANGE := 128.0
const MAGNUM_NOISE := 20.0

# Projectile config: heavier brass-toned bullet to read as a magnum round.
# Speed is 4x move_speed (set at fire time, see _fire_at).
const PROJECTILE_COLOR := Color(0.92, 0.66, 0.30)
const BASE_ACCURACY_DEG := 5.0  # mid-range between Rifleman (4) and HG (8)
const HUNT_VISION := 384.0
const SALVAGE_PER_KILL := 25
const CARRY_CAP := 25
const INTERACTION_RANGE := 80.0
const RETARGET_INTERVAL := 0.3

# Territorial farmer (DESIGN_MASTER §7.1, designed 2026-06-08).
# The Looter only hunts zombies whose CURRENT position is within
# LEASH_RADIUS_PX of its work anchor. The anchor defaults to the home
# Command Post on spawn; right-clicking ground re-stakes it. Hunt
# targets that wander out of leash are dropped. Income is emergent:
# Military noise pulls zombies into the leash zone where the Looter
# farms them; the Looter does NOT chase outside.
const LEASH_RADIUS_PX := 6.0 * 32.0
# Self-defense radius (2026-06-09 amendment). The leash filter alone
# can leave a Looter standing still while a zombie chews on it - any
# zombie outside the leash zone (anchor-distance > 192 px) but close
# enough to bite the Looter (Looter-distance < 36 px) was being
# filtered out by _find_zombie_to_hunt. "If I can hit it with my
# magnum, I will" - set to MAGNUM_RANGE so engagement is bounded by
# what the Looter can actually shoot. Slightly under the leash so
# territorial behavior dominates when both zones overlap.
const SELF_DEFENSE_RADIUS_PX := MAGNUM_RANGE
# Hold-at-anchor arrive band. Same value the old PATROL_ARRIVE_RANGE
# used; we keep the magic number under a clearer name now that the
# patrol state is repurposed as "walk back to anchor".
const ANCHOR_ARRIVE_RANGE := 48.0

# Speed flips with load (DESIGN_MASTER §7.1 v1, binary). Slow while
# working/hunting; fast while running scrap home. The burst only points
# homeward - this is what structurally prevents the Looter from being a
# rush unit (you cannot deploy it forward at the hauling speed). Both
# placeholders, lab-tunable.
const BASE_MOVE_SPEED := 60.0      # slow: working in the leash zone
const HAULING_MOVE_SPEED := 120.0  # fast: carrying scrap to the CP

# Carrying-loot avoidance: when a zombie is within AVOID_RANGE on the return
# trip, retarget the nav agent to a sidestep waypoint instead of straight
# home. The sidestep is computed from a perpendicular-to-threat offset blended
# with the home direction, so the Looter routes around the zombie via the
# nav mesh (not raw velocity steering - that was the original "sprinting
# off the map" bug). Restored from spec §4.1 per the design doc.
const AVOID_RANGE := 160.0
const AVOID_DETOUR_PX := 120.0
const AVOID_RETARGET_INTERVAL := 0.5

# Self-preservation kite. When the targeted zombie closes inside this range
# during HUNT_FIRE, the Looter backs away to maintain shooting distance
# instead of standing in place and getting bit. Per user feedback - Looters
# had no self-preservation, just stood there and took hits.
const KITE_BACKAWAY_RANGE := 56.0
const KITE_BACKAWAY_SPEED_MULT := 1.0  # full move speed while kiting

# Patrol scan cadence. Repurposed: while walking BACK to the work anchor
# (Sub.PATROL), the Looter looks for in-leash zombies every PATROL_SCAN
# _INTERVAL seconds so it can divert into a hunt instead of marching past.
const PATROL_SCAN_INTERVAL := 0.5

var _sub: Sub = Sub.NONE
var _target_zombie = null
var _home_base = null
var _carrying := 0
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
# Throttles _find_zombie_to_hunt scans from the NONE state. The scan
# iterates get_nodes_in_group("units") - at high zombie populations the
# unthrottled per-frame call was a measurable contributor to the
# late-game perf cliff (2026-06-08 diagnostic). Cadence matches the
# PATROL_SCAN_INTERVAL the patrol state already uses, so the idle scan
# rhythm and the patrol scan rhythm stay consistent.
var _hunt_scan_timer: float = 0.0

# Work anchor (DESIGN_MASTER §7.1). Set to the home CP position on _ready;
# rewritten by set_work_anchor() when the player right-clicks ground with
# this Looter selected (the right-click is staked into a farming order, not
# a raw move). Used by _find_zombie_to_hunt + _zombie_in_engagement_zone to constrain
# hunting to the zone around this point.
var _work_anchor: Vector2 = Vector2.ZERO

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

# Sprite root and per-action override. Substrate (CombatUnit) builds the
# SpriteFrames, picks the direction, and plays the animation. Looter's attack
# cadence is slower than Rifleman (magnum kick), so we override the speeds.
const SPRITE_ROOT := "res://assets/sprites/units/military/looter/"
const ATTACK_ANIM_HOLD := 0.45


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _sprite_anim_speeds() -> Dictionary:
	return {"idle": 4.0, "walk": 12.0, "attack": 14.0, "death": 8.0}


func _ready() -> void:
	super._ready()
	_init_sprite()
	# Anchor at the home CP on spawn. If for some reason no CP is owned
	# (test scenes, edge cases) fall back to the spawn position itself.
	var cp = _find_nearest_command_post()
	_work_anchor = cp.position if cp != null else global_position


func move_to(world_pos: Vector2) -> void:
	# Right-clicking ground with a Looter selected re-stakes the work
	# anchor at that spot instead of issuing a raw move order. The
	# Looter walks there (via the normal MOVE command); once arrived it
	# falls into the work loop and farms within LEASH_RADIUS of the new
	# anchor. This is how the player tells a Looter "go work that infested
	# house" without coding a separate verb.
	set_work_anchor(world_pos)
	super.move_to(world_pos)
	_sub = Sub.NONE
	_target_zombie = null


func set_work_anchor(world_pos: Vector2) -> void:
	_work_anchor = world_pos
	# Reset the hunt cycle so the next decision picks targets relative to
	# the new zone, not the old one.
	_target_zombie = null
	_sub = Sub.NONE


# Speed flips with load (DESIGN_MASTER §7.1 v1). Slow base when working
# in the leash zone; fast when running scrap home. Layered on top of the
# usual veterancy / suppression / squad multipliers so a suppressed
# loaded Looter is still slow per the suppression rules. Replaces
# Unit.get_effective_move_speed for this class.
func get_effective_move_speed() -> float:
	var base: float = HAULING_MOVE_SPEED if _carrying > 0 else BASE_MOVE_SPEED
	base *= speed_mult
	var sf = get_tree().get_first_node_in_group("suppression_field")
	if sf != null and sf.has_method("speed_multiplier_at"):
		base *= sf.speed_multiplier_at(global_position)
	return base


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer = max(0.0, _retarget_timer - delta)
	_hunt_scan_timer = max(0.0, _hunt_scan_timer - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()

	# Projectile-delayed kill detection. If kills_count incremented since last
	# tick, a projectile we fired landed and killed something. Award salvage
	# and transition to return-home, the same state changes the old inline
	# damage path produced at fire-time.
	if kills_count > _last_kills_count:
		var new_kills: int = kills_count - _last_kills_count
		_last_kills_count = kills_count
		_carrying = min(_carrying + new_kills * SALVAGE_PER_KILL, CARRY_CAP)
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
		Sub.PATROL:
			_tick_patrol(delta)
		_:
			velocity = Vector2.ZERO


func _pick_next_action() -> void:
	if _carrying > 0:
		_start_return_home()
		return
	_try_start_auto_hunt()


func _try_start_auto_hunt() -> void:
	# Throttled scan (2026-06-08 perf-cliff fix). _find_zombie_to_hunt
	# iterates get_nodes_in_group("units"); per-frame calls at 250+
	# zombies were a hot loop. While the cooldown is up we just hold at
	# anchor - identical no-target behavior, just postponed re-evaluation.
	# Determinism: delta accumulator on the physics tick, no wall-clock.
	if _hunt_scan_timer > 0.0:
		_hold_at_anchor()
		return
	_hunt_scan_timer = PATROL_SCAN_INTERVAL
	var z = _find_zombie_to_hunt()
	if z == null:
		# No in-leash target - hold at anchor (walk back if drifted).
		# This is the "territorial" guarantee: no zombie in our zone =
		# we don't roam looking for one.
		_hold_at_anchor()
		return
	_target_zombie = z
	_sub = Sub.HUNT_APPROACH
	_nav.target_position = z.global_position


func _hold_at_anchor() -> void:
	# If drifted off the anchor (e.g. chasing kited last shot or pushed
	# by separation), walk back. Otherwise stand still and wait for a
	# zombie to enter the zone (the noise/horde loop will pull them in).
	if global_position.distance_to(_work_anchor) > ANCHOR_ARRIVE_RANGE:
		_start_patrol()
	else:
		_sub = Sub.NONE
		velocity = Vector2.ZERO


func _start_patrol() -> void:
	# Repurposed (2026-06-08): the patrol state is now "walk back to the
	# work anchor", NOT roam to a random offset. The territorial
	# constraint means the Looter has exactly one place to go when
	# unoccupied - home.
	_patrol_target = _work_anchor
	_patrol_scan_timer = 0.0
	_sub = Sub.PATROL
	_nav.target_position = _work_anchor


func _tick_patrol(delta: float) -> void:
	# Mid-walk-back, look for in-leash zombies and divert to hunt if one
	# appears. The patrol target stays the anchor; only an actual target
	# inside the leash interrupts the walk.
	_patrol_scan_timer -= delta
	if _patrol_scan_timer <= 0.0:
		_patrol_scan_timer = PATROL_SCAN_INTERVAL
		var z = _find_zombie_to_hunt()
		if z != null:
			_target_zombie = z
			_sub = Sub.HUNT_APPROACH
			_nav.target_position = z.global_position
			return
	# Arrived at the anchor - stand still until next tick reconsiders.
	if global_position.distance_to(_patrol_target) <= ANCHOR_ARRIVE_RANGE or _nav.is_navigation_finished():
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_follow_navigation()


func _zombie_in_engagement_zone(z) -> bool:
	# Union of two zones (2026-06-09):
	#   1. Leash - zombie inside the territorial work area (anchor-centered).
	#      This is the original "this is my zone" rule, unchanged.
	#   2. Self-defense - zombie close enough to the LOOTER itself to be a
	#      personal threat, regardless of anchor distance. Without this, a
	#      Looter that's drifted off-anchor (or whose anchor sits at a corner
	#      while a zombie approaches from outside) just stands there and
	#      gets bit. "If I can shoot it, I will."
	# Self-defense radius < leash radius so territorial behavior dominates
	# when both zones overlap; the new branch only matters at the leash edge
	# and beyond.
	if z == null or not is_instance_valid(z):
		return false
	if _work_anchor.distance_to(z.global_position) <= LEASH_RADIUS_PX:
		return true
	if global_position.distance_to(z.global_position) <= SELF_DEFENSE_RADIUS_PX:
		return true
	return false


func _find_zombie_to_hunt():
	# Filters by engagement-zone (leash union self-defense, 2026-06-09).
	# Zombies inside the work zone qualify (territorial); zombies close to
	# the Looter's body qualify (self-defense) even when outside the leash.
	# Order matters for the cheap-cull: anchor-leash first since most idle
	# scans return a target from there; self-defense is the fallback that
	# catches the "zombie biting me on the leash edge" case.
	var best = null
	var best_dist := HUNT_VISION
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction != GameState.Faction.ZOMBIE:
			continue
		var in_leash: bool = _work_anchor.distance_to(u.global_position) <= LEASH_RADIUS_PX
		var d: float = global_position.distance_to(u.global_position)
		if not in_leash and d > SELF_DEFENSE_RADIUS_PX:
			continue
		if d <= best_dist:
			best_dist = d
			best = u
	return best


func _start_return_home() -> void:
	_home_base = _find_nearest_command_post()
	if _home_base == null:
		velocity = Vector2.ZERO
		return
	_sub = Sub.RETURN_HOME
	_nav.target_position = _home_base.position


# (Removed 2026-06-08: _start_return_to_hunt + _enter_search. The
# kill-memory loop they served is gone - the work anchor is now the
# canonical "where I work" and post-deposit the Looter just resumes the
# hunt cycle via _pick_next_action -> _try_start_auto_hunt.)


func _tick_hunt_approach() -> void:
	if _target_zombie == null or not is_instance_valid(_target_zombie):
		_sub = Sub.NONE
		return
	# Engagement-zone break: target left both the leash AND our self-defense
	# bubble. Drop it and re-scan next tick. Pre-2026-06-09 this was leash-only,
	# which abandoned kited targets that drifted 1 px past the leash edge.
	if not _zombie_in_engagement_zone(_target_zombie):
		_target_zombie = null
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
	if not _zombie_in_engagement_zone(_target_zombie):
		_target_zombie = null
		_sub = Sub.NONE
		return
	var dist := global_position.distance_to(_target_zombie.global_position)
	if dist > MAGNUM_RANGE * 1.2:
		_sub = Sub.HUNT_APPROACH
		return
	# Self-preservation: if the zombie is closing into bite range, back away
	# while continuing to fire. Without this the Looter just stands still and
	# gets bit because their fire rate (2.5s) is slower than the zombie's
	# closing speed.
	if dist < KITE_BACKAWAY_RANGE:
		var away: Vector2 = global_position - _target_zombie.global_position
		if away.length_squared() > 0.01:
			velocity = away.normalized() * get_effective_move_speed() * KITE_BACKAWAY_SPEED_MULT
			move_and_slide()
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	if _attack_cooldown <= 0.0:
		_attack_cooldown = MAGNUM_PERIOD
		_emit_magnum_noise()
		# Damage now resolves at projectile-impact time. The kills_count delta
		# check at the top of _physics_process picks up the kill credit and
		# triggers the return-home transition.
		_fire_at(_target_zombie)


func _fire_at(target) -> void:
	_attack_anim_timer = ATTACK_ANIM_HOLD
	# Suppression widens the cone at the shooter's position (DESIGN_MASTER §7.1).
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus) * _suppression_spread_multiplier()
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(MAGNUM_DAMAGE)),
		"speed": move_speed * 4.0,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 2.8,  # bullet radius in px
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
	# Defensive kills don't increase carry — already at cap. Routed through
	# resolve_damage so armor + size x type apply uniformly with
	# the projectile path (neutral matrix today; tuned later).
	var raw: float = float(get_effective_damage(MAGNUM_DAMAGE))
	z.take_damage(resolve_damage(raw, self, z), self)


# (Removed 2026-06-08: _tick_return_to_hunt + _tick_search. Their job -
# remember the last kill spot, walk back, then wander randomly looking
# for the next one - is subsumed by the work anchor and the per-tick
# in-leash scan in _try_start_auto_hunt / _tick_patrol.)


func _deposit_at_home() -> void:
	if _carrying > 0:
		# Routed through Unit.deposit_salvage so owner_controller (set by
		# AIController at spawn) decides the pool. Pre-fix, the AI-vs-AI
		# player-slot AI's Looters dumped to GameState (wrong) and the
		# opposing slot's Looters dumped to get_first_node_in_group(
		# "ai_controller") - always the player slot, never the opposing slot.
		# Net result: the opposing AI starved at 50 salvage forever.
		deposit_salvage(_carrying)
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
