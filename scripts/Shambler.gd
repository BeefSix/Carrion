extends "res://scripts/Unit.gd"

enum ZombieState { IDLE, ACQUIRING, INVESTIGATE, SEARCHING, CHASE, ATTACK }

# Per-type perception parameters. The Zombie Substrate spec specifies these
# as per-type so Shambler / Runner / Brute can each carry their own values;
# Shambler uses the baseline. When Runner / Brute land, they override.
#
# Vision:  4 tiles = 128 px, 90° forward cone
# Hearing: 12 tiles = 384 px, primary perception is vision (eyes good, ears average)
const VISION_RANGE_TILES := 4
const VISION_RANGE_PX := VISION_RANGE_TILES * 32.0
const VISION_CONE_DEG := 90.0
const VISION_CONE_HALF_RAD := deg_to_rad(VISION_CONE_DEG * 0.5)
const VISION_EDGE_FUZZ_RAD := deg_to_rad(10.0)
const HEARING_RANGE_TILES := 12
const HEARING_RANGE_PX := HEARING_RANGE_TILES * 32.0
# Hearing requires the attenuated magnitude to clear this threshold or the
# zombie treats the noise as background. Suppresses single-tile footfalls
# and other low-magnitude events from triggering investigation.
const HEARING_MIN_EFFECTIVE := 5.0
# Investigation arrives at noise position, then searches around it for
# this duration before returning to baseline wander.
const SEARCH_DURATION_MIN := 15.0
const SEARCH_DURATION_MAX := 20.0
const SEARCH_RADIUS := 60.0
const SEARCH_REPATH_INTERVAL := 3.0

const ACQUISITION_TIME_MIN := 0.5
const ACQUISITION_TIME_MAX := 1.5

# Idle head turns - zombie pivots its facing every 10-15 sec while standing
# still, simulating slow visual scanning. This is what makes peek-around-
# corner tactics nondeterministic; you don't know exactly which way the
# zombie is looking at any moment.
const HEAD_TURN_INTERVAL_MIN := 10.0
const HEAD_TURN_INTERVAL_MAX := 15.0
const FACING_PIVOT_RAD_PER_SEC := 4.0  # ~70 deg/sec, ~1.3 sec for full turn

const ATTACK_RANGE := 36.0
const LOST_TARGET_RANGE := 576.0
const ATTACK_DAMAGE := 8
const ATTACK_PERIOD := 1.0
const PERCEPTION_INTERVAL := 0.2  # 5 Hz perception update (was 0.3 retarget)
const INVESTIGATE_ARRIVE_RANGE := 60.0
const WANDER_RADIUS := 96.0
const WANDER_ARRIVE_RANGE := 30.0
# Phase 2: direction change cadence widened (was 4-10 sec; spec wants
# 15-30 sec so wanders feel like settled drift, not constant motion).
const WANDER_INTERVAL_MIN := 15.0
const WANDER_INTERVAL_MAX := 30.0
# Environmental preference weights applied when picking a new wander
# direction. Higher score = more likely to be picked. Direction sampling
# generates a handful of candidates, scores each by the env at its sample
# point, and weighted-random-selects.
const WANDER_CANDIDATES := 6
const WANDER_DECAY_TIER1_BONUS := 0.5  # decay > 50 within sample area
const WANDER_DECAY_TIER2_BONUS := 0.5  # decay > 100 stacks on top of tier 1
const WANDER_BUILDING_BONUS := 0.3     # 2+ buildings within ~6 tiles of sample
const WANDER_OPEN_PENALTY := 0.7       # multiplier when sample is open terrain
const WANDER_BUILDING_QUERY_RADIUS := 200.0  # ~6 tiles
const WANDER_DECAY_QUERY_TILES := 8
const TRIBAL_ALIGNED_COLOR := Color("5a5530")
# Force-spawned (Shaman ritual) zombies stay tribally-aligned for this many
# seconds, then revert to standard wild behavior. During the window they
# exempt all Tribal units from targeting, not just Walkers.
const TRIBAL_ALIGNMENT_DURATION := 30.0

@export var is_tribal_aligned: bool = false

var _tribal_alignment_timer: float = 0.0
var _baseline_body_color: Color = Color.WHITE

var _zombie_state: int = ZombieState.IDLE
var _target = null
var _investigate_target: Vector2 = Vector2.ZERO
var _attack_cooldown := 0.0
var _perception_timer := 0.0
var _wandering := false
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer := 0.0

# Vision / acquisition state.
var _acquiring_target = null
var _acquisition_timer: float = 0.0
var _facing_angle: float = 0.0          # current facing in radians
var _desired_facing_angle: float = 0.0  # angle we are pivoting toward
var _head_turn_timer: float = 0.0
# Hearing investigation state (SEARCHING phase after arriving at noise).
var _search_timer: float = 0.0
var _search_repath_timer: float = 0.0


func _ready() -> void:
	super._ready()
	_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
	_head_turn_timer = randf_range(HEAD_TURN_INTERVAL_MIN, HEAD_TURN_INTERVAL_MAX)
	# Initial facing: random cardinal-ish so spawned zombies aren't all
	# looking the same direction. Faces "south" by default before this.
	_facing_angle = randf() * TAU
	_desired_facing_angle = _facing_angle
	facing_dir = Vector2.from_angle(_facing_angle)
	# Preserve the original body color before the tribal-aligned override so
	# we can revert to it when the 30-sec timer expires.
	_baseline_body_color = body_color
	if is_tribal_aligned:
		body_color = TRIBAL_ALIGNED_COLOR
		_tribal_alignment_timer = TRIBAL_ALIGNMENT_DURATION
		queue_redraw()


func _draw() -> void:
	# Hunched / slumped variant of the humanoid silhouette. Shorter body,
	# wider shoulders sloping in, head pushed slightly forward and down,
	# no lightened head (decayed skin reads as uniform with the body). A
	# small forward-pointing tick on the head shows the current facing -
	# necessary for the player to understand whether the zombie can see
	# them. Subtle so it doesn't dominate the silhouette.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	var s_scale: float = float(size_px) / 22.0
	var sw: float = 14.0 * s_scale
	var sh: float = 5.0 * s_scale
	var bw: float = 10.0 * s_scale
	var bh: float = 12.0 * s_scale
	var hr: float = 4.0 * s_scale

	var head_offset_x: float = 1.5 * s_scale
	var head_y: float = -bh - hr * 0.15

	if selected:
		draw_arc(Vector2(0.0, 1.5), sw * 0.55, 0.0, TAU, 24, Color(1, 1, 0.4), 1.4, true)

	draw_colored_polygon(
		_ellipse_polygon(Vector2(0.0, 1.5), sw * 0.55, sh * 0.55),
		Color(0, 0, 0, 0.42),
	)

	draw_colored_polygon(PackedVector2Array([
		Vector2(-bw * 0.55, -bh + 3.0),
		Vector2(bw * 0.55, -bh + 3.0),
		Vector2(bw * 0.45, -1.0),
		Vector2(-bw * 0.45, -1.0),
	]), body_color)

	var head_pos := Vector2(head_offset_x, head_y)
	draw_circle(head_pos, hr, body_color)

	# Facing tick - small darker line from head in facing direction (projected
	# to iso so it points where the zombie is looking on screen).
	var iso_facing: Vector2 = Vector2(
		facing_dir.x - facing_dir.y,
		(facing_dir.x + facing_dir.y) * 0.75,
	)
	if iso_facing.length_squared() > 0.001:
		iso_facing = iso_facing.normalized()
		var tip: Vector2 = head_pos + iso_facing * (hr + 3.0)
		draw_line(head_pos + iso_facing * hr, tip, body_color.darkened(0.45), 1.6, true)

	var max_eff: int = get_effective_max_hp()
	if max_eff > 0 and current_hp < max_eff:
		var bar_w: float = max(18.0, float(size_px) * 0.9)
		var bar_y: float = head_y - hr - 5.0
		var bar_x: float = -bar_w * 0.5
		draw_rect(Rect2(bar_x, bar_y, bar_w, 2.5), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_eff)
		draw_rect(Rect2(bar_x, bar_y, bar_w * fill_ratio, 2.5), Color(0.35, 0.65, 0.3))


func investigate(world_pos: Vector2) -> void:
	if _zombie_state == ZombieState.CHASE or _zombie_state == ZombieState.ATTACK:
		return
	# If already investigating / searching this same area, refresh the
	# search timer instead of restarting (sustained noise extends interest).
	if (_zombie_state == ZombieState.INVESTIGATE or _zombie_state == ZombieState.SEARCHING) and \
		_investigate_target.distance_to(world_pos) < 50.0:
		if _zombie_state == ZombieState.SEARCHING:
			_search_timer = max(_search_timer, randf_range(SEARCH_DURATION_MIN, SEARCH_DURATION_MAX))
		return
	_investigate_target = world_pos
	_zombie_state = ZombieState.INVESTIGATE
	_wandering = false
	# Turn to face the noise as we head toward it. _tick_facing will pivot
	# us over ~1.3 sec - that's the spec's "1-2 second pivot" naturally.
	_set_desired_facing(world_pos)
	_nav.target_position = world_pos


# Called by NoiseField for every active emitter. Zombie filters by its own
# per-type hearing range and noise attenuation; triggers investigate() if
# the effective magnitude clears the threshold.
func hear_noise(noise_pos: Vector2, magnitude: float, distance: float) -> void:
	if distance > HEARING_RANGE_PX:
		return
	var attenuation: float = 1.0 - (distance / HEARING_RANGE_PX)
	var effective: float = magnitude * attenuation
	if effective < HEARING_MIN_EFFECTIVE:
		return
	investigate(noise_pos)


# Vision detection: distance, cone (with edge fuzziness), then LOS.
# Cheap filter first (distance + angle), expensive raycast last.
func _can_see(target_pos: Vector2) -> bool:
	var to_target: Vector2 = target_pos - global_position
	var distance: float = to_target.length()
	if distance > VISION_RANGE_PX:
		return false
	if distance < 1.0:
		return true
	var target_angle: float = to_target.angle()
	var angle_offset: float = absf(_angle_diff(_facing_angle, target_angle))
	if angle_offset > VISION_CONE_HALF_RAD:
		return false
	# Edge fuzziness: targets within VISION_EDGE_FUZZ_RAD of the cone
	# boundary detect at 50% per perception tick instead of 100%.
	if angle_offset > VISION_CONE_HALF_RAD - VISION_EDGE_FUZZ_RAD:
		if randf() > 0.5:
			return false
	# LOS: walk segment against every building/wall rect. Buildings and
	# walls block; ground, fences, other units do NOT block.
	if not _has_los(target_pos):
		return false
	return true


func _has_los(target_pos: Vector2) -> bool:
	# Segment-vs-rect for every building in range. Bounding box pre-filter
	# rejects buildings entirely outside the segment AABB so we only run
	# the 4-edge intersection test on candidates that could possibly block.
	var seg_min: Vector2 = global_position.min(target_pos)
	var seg_max: Vector2 = global_position.max(target_pos)
	var seg_aabb := Rect2(seg_min, seg_max - seg_min).grow(8.0)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b == self:
			continue
		if not ("size_pixels" in b):
			continue
		var half: Vector2 = b.size_pixels * 0.5
		var brect := Rect2(b.position - half, b.size_pixels)
		if not seg_aabb.intersects(brect):
			continue
		if _segment_intersects_rect(global_position, target_pos, brect):
			return false
	return true


func _segment_intersects_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	# Endpoint inside the rect? Counts as blocked (target is inside the
	# building, e.g., a unit standing on a building tile - shouldn't happen
	# in practice but we handle defensively).
	if rect.has_point(p1) or rect.has_point(p2):
		return true
	var tl: Vector2 = rect.position
	var tr: Vector2 = rect.position + Vector2(rect.size.x, 0.0)
	var br: Vector2 = rect.position + rect.size
	var bl: Vector2 = rect.position + Vector2(0.0, rect.size.y)
	if Geometry2D.segment_intersects_segment(p1, p2, tl, tr) != null:
		return true
	if Geometry2D.segment_intersects_segment(p1, p2, tr, br) != null:
		return true
	if Geometry2D.segment_intersects_segment(p1, p2, br, bl) != null:
		return true
	if Geometry2D.segment_intersects_segment(p1, p2, bl, tl) != null:
		return true
	return false


func _angle_diff(a: float, b: float) -> float:
	# Shortest-angle difference (-PI to +PI).
	var d: float = b - a
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return d


func _set_desired_facing(target_pos: Vector2) -> void:
	var to_target: Vector2 = target_pos - global_position
	if to_target.length_squared() < 1.0:
		return
	_desired_facing_angle = to_target.angle()


func _tick_facing(delta: float) -> void:
	# Pivot _facing_angle toward _desired_facing_angle at a capped rate, so
	# turns are visible to the player rather than instant snap.
	var diff: float = _angle_diff(_facing_angle, _desired_facing_angle)
	if absf(diff) < 0.02:
		return
	var step: float = FACING_PIVOT_RAD_PER_SEC * delta
	if absf(diff) < step:
		_facing_angle = _desired_facing_angle
	else:
		_facing_angle += sign(diff) * step
	facing_dir = Vector2.from_angle(_facing_angle)
	queue_redraw()


func _tick_idle_head_turn(delta: float) -> void:
	# Stationary zombies pivot to a new random direction every 10-15 sec.
	# Skipped if currently pivoting (don't pile new turns on existing).
	if absf(_angle_diff(_facing_angle, _desired_facing_angle)) > 0.05:
		return
	_head_turn_timer -= delta
	if _head_turn_timer <= 0.0:
		_head_turn_timer = randf_range(HEAD_TURN_INTERVAL_MIN, HEAD_TURN_INTERVAL_MAX)
		# Pick a new angle within +/- 120 degrees of current facing.
		_desired_facing_angle = _facing_angle + randf_range(-2.094, 2.094)


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_tick_facing(delta)
	# Drop tribal alignment when the timer runs out (force-spawned zombies
	# revert to standard wild behavior).
	if is_tribal_aligned:
		_tribal_alignment_timer -= delta
		if _tribal_alignment_timer <= 0.0:
			is_tribal_aligned = false
			body_color = _baseline_body_color
			queue_redraw()

	# Perception at 5 Hz - vision detection (cone + range; LOS in commit 2).
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = PERCEPTION_INTERVAL
		_update_perception(delta)
		if _target != null and _zombie_state == ZombieState.CHASE:
			_nav.target_position = _target.global_position

	match _zombie_state:
		ZombieState.IDLE:
			_tick_idle_head_turn(delta)
			_tick_wander(delta)
		ZombieState.ACQUIRING:
			# Lock facing on the acquiring target and tick the acquisition
			# timer. If target moves out of vision, drop back to IDLE.
			if _acquiring_target == null or not is_instance_valid(_acquiring_target):
				_zombie_state = ZombieState.IDLE
				_acquiring_target = null
				return
			_set_desired_facing(_acquiring_target.global_position)
			velocity = Vector2.ZERO
			_acquisition_timer -= delta
			if _acquisition_timer <= 0.0:
				_target = _acquiring_target
				_acquiring_target = null
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
		ZombieState.INVESTIGATE:
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
			elif global_position.distance_to(_investigate_target) <= INVESTIGATE_ARRIVE_RANGE:
				# Arrived at the noise but no target spotted - enter
				# investigative wandering for 15-20 sec.
				_zombie_state = ZombieState.SEARCHING
				_search_timer = randf_range(SEARCH_DURATION_MIN, SEARCH_DURATION_MAX)
				_search_repath_timer = 0.0
				velocity = Vector2.ZERO
			else:
				_set_desired_facing(_investigate_target)
				_follow_navigation()
		ZombieState.SEARCHING:
			# Wander in a small radius around the noise position. Drops back
			# to IDLE when the timer expires or transitions to CHASE if a
			# target is spotted mid-search.
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
				return
			_search_timer -= delta
			if _search_timer <= 0.0:
				_zombie_state = ZombieState.IDLE
				velocity = Vector2.ZERO
				return
			_search_repath_timer -= delta
			if _search_repath_timer <= 0.0:
				_search_repath_timer = SEARCH_REPATH_INTERVAL
				var offset := Vector2(
					randf_range(-SEARCH_RADIUS, SEARCH_RADIUS),
					randf_range(-SEARCH_RADIUS, SEARCH_RADIUS),
				)
				var search_pos: Vector2 = _investigate_target + offset
				search_pos.x = clamp(search_pos.x, 50.0, 6094.0)
				search_pos.y = clamp(search_pos.y, 50.0, 6094.0)
				_nav.target_position = search_pos
				_set_desired_facing(search_pos)
			_follow_navigation()
		ZombieState.CHASE:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			_set_desired_facing(_target.global_position)
			var dist: float = global_position.distance_to(_target.global_position)
			if dist <= ATTACK_RANGE:
				_zombie_state = ZombieState.ATTACK
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		ZombieState.ATTACK:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			_set_desired_facing(_target.global_position)
			var dist2: float = global_position.distance_to(_target.global_position)
			if dist2 > ATTACK_RANGE * 1.2:
				_zombie_state = ZombieState.CHASE
				return
			velocity = Vector2.ZERO
			if _attack_cooldown <= 0:
				if _target.has_method("take_damage"):
					_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
				_attack_cooldown = ATTACK_PERIOD


func _tick_wander(delta: float) -> void:
	if _wandering:
		if global_position.distance_to(_wander_target) <= WANDER_ARRIVE_RANGE or _nav.is_navigation_finished():
			_wandering = false
			_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
			velocity = Vector2.ZERO
		else:
			_set_desired_facing(_wander_target)
			_follow_navigation()
	else:
		velocity = Vector2.ZERO
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_start_wander()


func _start_wander() -> void:
	# Phase 2: directional wandering with environmental texture instead of
	# pure random offset. Candidate directions are sampled around the
	# zombie, each scored by the environment at its projected sample point;
	# the new heading is a weighted-random pick. Decay zones, building
	# clusters pull the zombie in; open wilderness pushes it away.
	var direction: Vector2 = _pick_wander_direction()
	var target: Vector2 = global_position + direction * WANDER_RADIUS
	target.x = clamp(target.x, 50.0, 6094.0)
	target.y = clamp(target.y, 50.0, 6094.0)
	_wander_target = target
	_wandering = true
	_nav.target_position = _wander_target


func _pick_wander_direction() -> Vector2:
	# Sample WANDER_CANDIDATES directions evenly spaced around the circle
	# with small per-candidate angle jitter, then weighted-random by
	# environmental score.
	var candidates: Array[Vector2] = []
	var scores: Array[float] = []
	var base_jitter: float = randf() * TAU  # random rotational offset so we don't always sample the same angles
	for i in range(WANDER_CANDIDATES):
		var angle: float = base_jitter + (float(i) / float(WANDER_CANDIDATES)) * TAU + randf_range(-0.25, 0.25)
		var dir: Vector2 = Vector2.from_angle(angle)
		candidates.append(dir)
		scores.append(_score_wander_direction(dir))
	# Weighted random pick.
	var total_score: float = 0.0
	for s in scores:
		total_score += s
	if total_score <= 0.0:
		return candidates[randi() % candidates.size()]
	var roll: float = randf() * total_score
	var acc: float = 0.0
	for i in range(candidates.size()):
		acc += scores[i]
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func _score_wander_direction(dir: Vector2) -> float:
	var sample_pos: Vector2 = global_position + dir * WANDER_RADIUS
	var score: float = 1.0
	# Decay attraction - sample tile's value via the field's
	# get_value_at(world_pos). Stacked tiers so heavily decayed areas pull
	# harder.
	var df = get_tree().get_first_node_in_group("decay_field")
	if df != null and df.has_method("get_value_at"):
		var d_val: float = df.get_value_at(sample_pos)
		if d_val > 50.0:
			score += WANDER_DECAY_TIER1_BONUS
		if d_val > 100.0:
			score += WANDER_DECAY_TIER2_BONUS
	# Building cluster attraction - count buildings within query radius,
	# short-circuit at 2 because we just need to know "is there a cluster
	# here" not exact density.
	var bldg_count: int = 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.position.distance_to(sample_pos) < WANDER_BUILDING_QUERY_RADIUS:
			bldg_count += 1
			if bldg_count >= 2:
				break
	if bldg_count >= 2:
		score += WANDER_BUILDING_BONUS
	# Open terrain avoidance - query the ground tile under sample point.
	# bare_ground / dirt_road / vegetation register as "open" / wild.
	var gt = get_tree().get_first_node_in_group("ground_tiles")
	if gt != null and gt.has_method("get_tile_type_at"):
		var tt: int = gt.get_tile_type_at(sample_pos)
		# Constants match GroundTiles palette indices: 6 bare, 7 dirt road,
		# 8 vegetation.
		if tt == 6 or tt == 7 or tt == 8:
			score *= WANDER_OPEN_PENALTY
	return max(0.1, score)


# Perception update - replaces the old _update_target. Vision now requires
# the target to be in range AND in the facing cone (and later, LOS). When
# a new target is seen, the zombie enters ACQUIRING for 0.5-1.5 seconds
# before committing to CHASE.
func _update_perception(_delta: float) -> void:
	# If already chasing/attacking a valid target, keep going.
	if _zombie_state == ZombieState.CHASE or _zombie_state == ZombieState.ATTACK:
		if _target != null and is_instance_valid(_target):
			return
		_target = null
	var best = _find_visible_target()
	if best == null:
		# Lost vision while acquiring -> drop acquisition.
		if _zombie_state == ZombieState.ACQUIRING:
			_acquiring_target = null
			_zombie_state = ZombieState.IDLE
		_target = null
		return
	# Target visible. If we're already acquiring this target, the timer
	# (in _physics_process match block) handles the commit.
	if _zombie_state == ZombieState.ACQUIRING and _acquiring_target == best:
		return
	# Start acquisition.
	_acquiring_target = best
	_acquisition_timer = randf_range(ACQUISITION_TIME_MIN, ACQUISITION_TIME_MAX)
	_zombie_state = ZombieState.ACQUIRING


func _find_visible_target():
	# Per spec: only Walkers are exempt from all zombie targeting. Tribal
	# Hunters and Shamans are detected normally. Tribally-aligned zombies
	# (force-spawned) exempt all Tribal during their 30-sec alignment.
	var best = null
	var best_dist: float = VISION_RANGE_PX
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == Faction.ZOMBIE:
			continue
		# Walkers are always invisible to zombie targeting - the load-bearing
		# Tribal identity mechanic.
		if u.is_in_group("walkers"):
			continue
		# Force-spawned zombies treat all Tribal as ally during the 30-sec
		# alignment window.
		if is_tribal_aligned and u.faction == Faction.TRIBAL:
			continue
		if not _can_see(u.global_position):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best
