extends "res://scripts/Unit.gd"

enum ZombieState { IDLE, ACQUIRING, INVESTIGATE, SEARCHING, LOST_TARGET, CHASE, ATTACK }

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
# Anti-thrash radius - new noise within this distance of an active
# investigation / search location is treated as reinforcement of the
# existing investigation, not as a fresh one. Bumped from 50 px to 8
# tiles (256 px) per Phase 2 spec.
const PERSIST_RADIUS_PX := 256.0

# Phase 2 acquisition delay scales with where the target sits within the
# vision cone. Close + cone-center = fastest commit (target is unmistakable);
# at edge or near max range = slower (could be a glimpse). Makes peeks at
# close range risky and at distance safer.
const ACQUISITION_CENTER_MIN := 0.4
const ACQUISITION_CENTER_MAX := 0.8
const ACQUISITION_EDGE_MIN := 1.2
const ACQUISITION_EDGE_MAX := 2.0
# Phase 2 range fuzziness - detection probability per perception tick
# scales toward 0 at the edge of vision range.
const RANGE_FUZZ_NEAR := 0.75  # at <75% range -> 100% detect
const RANGE_FUZZ_FAR := 0.9    # 75-90% range -> 75% detect; 90-100% -> 40%
const RANGE_FUZZ_PROB_NEAR := 0.75
const RANGE_FUZZ_PROB_FAR := 0.40
# Phase 2 hearing magnitude stochasticity - noise events near threshold
# only sometimes trigger investigation. >=HEARING_RELIABLE always; in
# the band [HEARING_MIN_EFFECTIVE..HEARING_RELIABLE] probability scales
# linearly between HEARING_PROB_MIN and HEARING_PROB_MAX.
const HEARING_RELIABLE := 15.0
const HEARING_PROB_MIN := 0.30
const HEARING_PROB_MAX := 0.70

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
# Direction change cadence: 10-20 sec is the sweet spot for legibility at
# 4x speed. 15-30 sec felt mechanically straight-line because direction
# events were too rare for the eye to see them as deliberation.
const WANDER_INTERVAL_MIN := 10.0
const WANDER_INTERVAL_MAX := 20.0
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

# Cluster drift. Idle zombies bias wanders toward nearby idle-zombie
# centroids. Tuning prioritizes visible tight clods - higher bias rate,
# longer travel toward centroid, higher crowding threshold so clusters
# pack visibly before the soft cap kicks in.
const CLUSTER_FAR_RADIUS_PX := 12.0 * 32.0    # 12 tiles - cluster membership query
const CLUSTER_CLOSE_RADIUS_PX := 4.0 * 32.0   # 4 tiles - crowding query (was 6)
const CLUSTER_BIAS_PROBABILITY := 0.45        # Bumped back up from 0.10 - density gradient can't seed clusters out of sparse populations; centroid bias is the cold-start mechanism

# Cluster cohesion: once a zombie is in a tight cluster (2+ neighbors
# within ~5 tiles), copy the nearest neighbor's active wander target
# instead of picking independently. Keeps formed groups moving as one
# unit instead of dispersing on independent direction picks.
const COHESION_RADIUS_PX := 10.0 * 32.0     # 10 tiles - wider catchment
const COHESION_PROBABILITY := 0.95           # almost always follow a wandering leader
const COHESION_NEIGHBOR_THRESHOLD := 1       # even one neighbor counts now
const COHESION_TARGET_JITTER := 14.0         # tight formation spread

# Magnetic pull: zombies are aware of other zombies out to 14 tiles and
# heavily bias their wander toward the nearest one. This is the "sightlines
# and affinity to hang out" the user asked for - independent of whether
# a leader is currently wandering. Lone zombies who see another zombie
# pull toward them; clusters with no active leader still tighten.
const MAGNETIC_RADIUS_PX := 14.0 * 32.0     # 14 tiles
const MAGNETIC_PROBABILITY := 0.75           # 75% of direction picks just head to nearest zombie
const MAGNETIC_TRAVEL_FRACTION := 0.75       # travel 75% of the way (vs all the way - leaves room for jostle)
const MAGNETIC_TRAVEL_MAX_PX := 280.0        # cap per cycle so cross-map magnetic doesn't teleport

# Cluster stickiness: once a zombie is in a populated ZombieField cell,
# its wander picks should mostly shuffle in place and its timer should
# tick down slower. Without this, the 25% of picks that fall through
# the magnetic check end up doing 96 px env-scored wanders - that's the
# "running off in different directions" the user reported.
const CLUSTER_SHUFFLE_DENSITY_THRESHOLD := 3   # captain-of-cluster shuffles 80% of picks at this density
const CLUSTER_SHUFFLE_PROBABILITY := 0.80
const CLUSTER_SHUFFLE_RADIUS_PX := 24.0

# Captain pattern (replaces previous per-zombie wander timers as the
# coordination mechanism). The lowest-instance-ID zombie within
# COHESION_RADIUS_PX of a position is captain of that local cluster.
# Captains tick their wander timer and pick directions normally;
# followers (everyone else) skip the wander entirely and stand still
# until pulled along by the captain's _propagate_wander_to_cluster.
# This makes cohesion structural, not probabilistic - clusters can no
# longer disperse from accumulated independent picks because only one
# zombie per cluster is allowed to pick.
const CAPTAIN_CHECK_INTERVAL := 0.5

# Phase 2.5 state cascade: when one zombie transitions IDLE -> INVESTIGATE
# or IDLE -> ACQUIRING, nearby idle zombies have a chance to follow with
# delayed propagation. Damped through three rings - primary 35%, secondary
# 20%, tertiary 10% - so the wave dies out naturally.
const CASCADE_RADIUS_PX := 8.0 * 32.0
const CASCADE_PROB_PRIMARY := 0.35     # level 0 originator -> recipients
const CASCADE_PROB_SECONDARY := 0.20   # level 1 (joined primary) -> recipients
const CASCADE_PROB_TERTIARY := 0.10    # level 2+ (joined secondary or beyond)
const CASCADE_MAX_LEVEL := 3           # stop propagating past tertiary ring
const CASCADE_DELAY_MIN := 1.0
const CASCADE_DELAY_MAX := 3.0
const CLUSTER_CROWD_THRESHOLD := 14           # 14+ within close radius -> repel (was 8)
const CLUSTER_TRAVEL_FRACTION := 0.6          # how much of centroid distance to travel each wander
const CLUSTER_TRAVEL_MAX_PX := 220.0          # cap so a single wander step doesn't teleport across the map
const CLUSTER_REPEL_DISTANCE_PX := 120.0      # how far to push when crowded
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
# LOST_TARGET state remembers where the lost target was last seen so the
# zombie can walk there before giving up.
var _last_known_pos: Vector2 = Vector2.ZERO
# Captain pattern: cached "am I the cluster captain" flag, refreshed at
# CAPTAIN_CHECK_INTERVAL. True if no other zombie within COHESION_RADIUS_PX
# has a lower instance_id than ours (or if we have no nearby zombies, in
# which case we're trivially captain of a one-zombie "cluster").
var _is_captain: bool = true
var _captain_check_timer: float = 0.0
# Cascade pending state - level we joined at (-1 = no pending), the
# stimulus we'll investigate when the delay timer fires, and the timer.
var _pending_cascade_level: int = -1
var _pending_cascade_stimulus: Vector2 = Vector2.ZERO
var _pending_cascade_timer: float = 0.0


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


func investigate(world_pos: Vector2, cascade_join_level: int = -1) -> void:
	# cascade_join_level: -1 means this is an originating investigation
	# (gunshot heard, noise emitter triggered, etc.) and outbound broadcast
	# is primary (level 0). Otherwise the zombie joined a cascade at that
	# level, and outbound broadcast is at level + 1 with damped probability.
	if _zombie_state == ZombieState.CHASE or _zombie_state == ZombieState.ATTACK:
		return
	if _zombie_state == ZombieState.LOST_TARGET:
		return
	if (_zombie_state == ZombieState.INVESTIGATE or _zombie_state == ZombieState.SEARCHING) and \
		_investigate_target.distance_to(world_pos) < PERSIST_RADIUS_PX:
		if _zombie_state == ZombieState.SEARCHING:
			_search_timer = max(_search_timer, randf_range(SEARCH_DURATION_MIN, SEARCH_DURATION_MAX))
		return
	var was_idle: bool = (_zombie_state == ZombieState.IDLE)
	_investigate_target = world_pos
	_zombie_state = ZombieState.INVESTIGATE
	_wandering = false
	_set_desired_facing(world_pos)
	_nav.target_position = world_pos
	# Cascade broadcast on IDLE -> INVESTIGATE transition only. Originators
	# broadcast primary; cascade-followers broadcast next-level-up.
	if was_idle:
		var out_level: int = 0 if cascade_join_level < 0 else cascade_join_level + 1
		_broadcast_cascade(world_pos, out_level)


# Called by another zombie's _broadcast_cascade when this zombie is within
# the cascade radius and the probability roll passed. We queue a delayed
# investigate; the delay (1-3 sec randomized) is what produces visible
# wave propagation through the cluster.
func on_cascade(stimulus_pos: Vector2, level: int) -> void:
	if level > CASCADE_MAX_LEVEL:
		return
	if _zombie_state != ZombieState.IDLE:
		return
	if _pending_cascade_level >= 0:
		return  # already have a pending cascade; ignore subsequent triggers
	_pending_cascade_stimulus = stimulus_pos
	_pending_cascade_level = level
	_pending_cascade_timer = randf_range(CASCADE_DELAY_MIN, CASCADE_DELAY_MAX)


func _broadcast_cascade(stimulus_pos: Vector2, level: int) -> void:
	if level > CASCADE_MAX_LEVEL:
		return
	var prob: float = CASCADE_PROB_PRIMARY
	if level == 1:
		prob = CASCADE_PROB_SECONDARY
	elif level >= 2:
		prob = CASCADE_PROB_TERTIARY
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		if not other.has_method("on_cascade"):
			continue
		if not (other.has_method("is_currently_idle") and other.is_currently_idle()):
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > CASCADE_RADIUS_PX:
			continue
		if randf() > prob:
			continue
		other.on_cascade(stimulus_pos, level)


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
	# Phase 2 stochasticity: in the [HEARING_MIN_EFFECTIVE, HEARING_RELIABLE]
	# band the noise might or might not trigger investigation. Probability
	# scales linearly from HEARING_PROB_MIN at threshold to HEARING_PROB_MAX
	# at reliable. Above HEARING_RELIABLE always triggers.
	if effective < HEARING_RELIABLE:
		var t: float = (effective - HEARING_MIN_EFFECTIVE) / (HEARING_RELIABLE - HEARING_MIN_EFFECTIVE)
		var trigger_prob: float = lerp(HEARING_PROB_MIN, HEARING_PROB_MAX, t)
		if randf() > trigger_prob:
			return
	investigate(noise_pos)


func _compute_acquisition_delay(target_pos: Vector2) -> float:
	# Acquisition timer scales with how "definitive" the sighting is.
	# A target dead-center in the cone at close range is unmistakable
	# (0.4-0.8 sec). A target glimpsed at the cone edge or near max range
	# takes longer to commit to (1.2-2.0 sec). Edge_factor is the max of
	# the angular fraction (offset / cone-half) and the range fraction
	# (distance / max-range), each clamped to [0..1].
	var to_target: Vector2 = target_pos - global_position
	var distance: float = to_target.length()
	var range_factor: float = clamp(distance / VISION_RANGE_PX, 0.0, 1.0)
	var angle_offset: float = absf(_angle_diff(_facing_angle, to_target.angle()))
	var angle_factor: float = clamp(angle_offset / VISION_CONE_HALF_RAD, 0.0, 1.0)
	var edge_factor: float = maxf(range_factor, angle_factor)
	var center_time: float = randf_range(ACQUISITION_CENTER_MIN, ACQUISITION_CENTER_MAX)
	var edge_time: float = randf_range(ACQUISITION_EDGE_MIN, ACQUISITION_EDGE_MAX)
	return lerp(center_time, edge_time, edge_factor)


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
	# Edge-of-cone fuzziness (Phase 1): targets within VISION_EDGE_FUZZ_RAD
	# of the cone boundary detect at 50% per tick instead of 100%.
	if angle_offset > VISION_CONE_HALF_RAD - VISION_EDGE_FUZZ_RAD:
		if randf() > 0.5:
			return false
	# Range fuzziness (Phase 2): probability drops toward the max range
	# edge. Beyond 75% range partial chance; beyond 90% range slim chance.
	var range_factor: float = distance / VISION_RANGE_PX
	if range_factor > RANGE_FUZZ_FAR:
		if randf() > RANGE_FUZZ_PROB_FAR:
			return false
	elif range_factor > RANGE_FUZZ_NEAR:
		if randf() > RANGE_FUZZ_PROB_NEAR:
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
			# Pending cascade timer: when it fires, transition to INVESTIGATE
			# with the level we joined at so re-broadcast damps correctly.
			if _pending_cascade_level >= 0:
				_pending_cascade_timer -= delta
				if _pending_cascade_timer <= 0.0:
					var join_lvl: int = _pending_cascade_level
					var stim: Vector2 = _pending_cascade_stimulus
					_pending_cascade_level = -1
					investigate(stim, join_lvl)
					return
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
		ZombieState.LOST_TARGET:
			# Walk to the last position we saw the target. _update_perception
			# handles re-acquisition if they reappear. Arriving transitions
			# to SEARCHING at that location for the 15-20 sec timer.
			if global_position.distance_to(_last_known_pos) <= INVESTIGATE_ARRIVE_RANGE:
				_investigate_target = _last_known_pos
				_zombie_state = ZombieState.SEARCHING
				_search_timer = randf_range(SEARCH_DURATION_MIN, SEARCH_DURATION_MAX)
				_search_repath_timer = 0.0
				velocity = Vector2.ZERO
			else:
				_set_desired_facing(_last_known_pos)
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
		# Captain pattern: only the cluster's captain (lowest instance_id
		# within COHESION_RADIUS_PX) actually counts down its wander timer.
		# Everyone else stands still until the captain pulls them along
		# via _propagate_wander_to_cluster. Refresh captain status every
		# CAPTAIN_CHECK_INTERVAL seconds to amortize the O(N) check.
		_captain_check_timer -= delta
		if _captain_check_timer <= 0.0:
			_captain_check_timer = CAPTAIN_CHECK_INTERVAL
			_refresh_captain_status()
		if not _is_captain:
			return
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_start_wander()


func _refresh_captain_status() -> void:
	var my_id: int = get_instance_id()
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		if global_position.distance_to(other.global_position) > COHESION_RADIUS_PX:
			continue
		if other.get_instance_id() < my_id:
			_is_captain = false
			return
	_is_captain = true


func _start_wander() -> void:
	# Direction selection priority:
	#   0. Shuffle-in-place: if we're sitting in a populated ZombieField
	#      cell (3+ zombies), 80% chance to just pick a tiny offset from
	#      current position. Clusters stay put 4 out of 5 cycles.
	#   1. Cohesion: copy a wandering leader's target.
	#   2. Magnetic: head toward the nearest zombie within 14 tiles.
	#   3. Env-scored: density / decay / buildings / open terrain pick.
	# After picking, push our target to nearby idle neighbors.
	var target: Vector2 = Vector2.ZERO
	var local_density: int = _zombie_field_density_here()
	if local_density >= CLUSTER_SHUFFLE_DENSITY_THRESHOLD and randf() < CLUSTER_SHUFFLE_PROBABILITY:
		target = global_position + Vector2(
			randf_range(-CLUSTER_SHUFFLE_RADIUS_PX, CLUSTER_SHUFFLE_RADIUS_PX),
			randf_range(-CLUSTER_SHUFFLE_RADIUS_PX, CLUSTER_SHUFFLE_RADIUS_PX),
		)
	if target == Vector2.ZERO and randf() < COHESION_PROBABILITY:
		target = _find_cluster_leader_target()
	if target == Vector2.ZERO and randf() < MAGNETIC_PROBABILITY:
		target = _find_magnetic_target()
	if target == Vector2.ZERO:
		var direction: Vector2 = _pick_wander_direction()
		target = global_position + direction * WANDER_RADIUS
	target.x = clamp(target.x, 50.0, 6094.0)
	target.y = clamp(target.y, 50.0, 6094.0)
	_wander_target = target
	_wandering = true
	_nav.target_position = _wander_target
	_propagate_wander_to_cluster()


func _zombie_field_density_here() -> int:
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf == null or not zf.has_method("get_density_at"):
		return 0
	return zf.get_density_at(global_position)


func _find_magnetic_target() -> Vector2:
	# Sightlines-and-affinity: pull toward the nearest zombie within
	# MAGNETIC_RADIUS regardless of whether they're wandering. Doesn't
	# require any in-cluster status; works on isolated zombies that
	# can see each other across open ground.
	var nearest = null
	var nearest_dist: float = MAGNETIC_RADIUS_PX
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = other
	if nearest == null:
		return Vector2.ZERO
	var to_them: Vector2 = nearest.global_position - global_position
	if to_them.length_squared() < 1.0:
		return Vector2.ZERO
	var travel: float = minf(nearest_dist * MAGNETIC_TRAVEL_FRACTION, MAGNETIC_TRAVEL_MAX_PX)
	return global_position + to_them.normalized() * travel


func _propagate_wander_to_cluster() -> void:
	# We just started wandering. Any nearby idle zombie who hasn't yet
	# started their own wander gets pulled along with our destination
	# (with small jitter). They reset their own _wander_timer so they
	# don't immediately repick on next cycle.
	var nearby_followers: Array = []
	var nearby_count: int = 0
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > COHESION_RADIUS_PX:
			continue
		nearby_count += 1
		if other.has_method("follow_leader_wander"):
			nearby_followers.append(other)
	if nearby_count < COHESION_NEIGHBOR_THRESHOLD:
		return
	for f in nearby_followers:
		if randf() < COHESION_PROBABILITY:
			f.follow_leader_wander(_wander_target)


func follow_leader_wander(leader_target: Vector2) -> void:
	# Called by a cluster leader who just picked a wander direction. We
	# adopt their target with jitter and start moving immediately,
	# regardless of our own _wander_timer state. Only fires if we are
	# IDLE and not already wandering somewhere of our own.
	if _zombie_state != ZombieState.IDLE:
		return
	if _wandering:
		return
	var jittered: Vector2 = leader_target + Vector2(
		randf_range(-COHESION_TARGET_JITTER, COHESION_TARGET_JITTER),
		randf_range(-COHESION_TARGET_JITTER, COHESION_TARGET_JITTER),
	)
	jittered.x = clamp(jittered.x, 50.0, 6094.0)
	jittered.y = clamp(jittered.y, 50.0, 6094.0)
	_wander_target = jittered
	_wandering = true
	_nav.target_position = _wander_target
	# Reset our timer so we don't immediately repick on next cycle.
	_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)


# Public accessor so other Shamblers in the same cluster can copy our
# travel destination. Returns ZERO if we're not actively wandering or
# not in IDLE state (don't propagate chase/investigate targets).
func get_active_wander_target() -> Vector2:
	if _wandering and _zombie_state == ZombieState.IDLE:
		return _wander_target
	return Vector2.ZERO


func _find_cluster_leader_target() -> Vector2:
	# Look for nearby zombies who already have an active wander destination.
	# Require COHESION_NEIGHBOR_THRESHOLD+ total neighbors so we don't trigger
	# cohesion when paired with just one other zombie - that's a wandering
	# pair, not a cluster. Return the nearest leader's target with jitter
	# so followers spread slightly instead of stacking.
	var leader = null
	var leader_dist: float = INF
	var nearby_count: int = 0
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > COHESION_RADIUS_PX:
			continue
		nearby_count += 1
		if not other.has_method("get_active_wander_target"):
			continue
		var t: Vector2 = other.get_active_wander_target()
		if t == Vector2.ZERO:
			continue
		if d < leader_dist:
			leader_dist = d
			leader = other
	if nearby_count < COHESION_NEIGHBOR_THRESHOLD or leader == null:
		return Vector2.ZERO
	var leader_target: Vector2 = leader.get_active_wander_target()
	return leader_target + Vector2(
		randf_range(-COHESION_TARGET_JITTER, COHESION_TARGET_JITTER),
		randf_range(-COHESION_TARGET_JITTER, COHESION_TARGET_JITTER),
	)


# Public so other Shamblers can check whether to include this one in their
# cluster centroid calculation. Active states (chasing, investigating,
# acquiring) should not anchor clusters; only truly-idle zombies do.
func is_currently_idle() -> bool:
	return _zombie_state == ZombieState.IDLE


func _cluster_bias_target() -> Vector2:
	# Returns a world-space target that biases this wander toward (or away
	# from) the idle-zombie cluster centroid. Vector2.ZERO if no neighbors
	# qualify (caller falls through to env-scored pick).
	#
	# Travel distance: CLUSTER_TRAVEL_FRACTION * distance-to-centroid,
	# capped at CLUSTER_TRAVEL_MAX_PX so big sparse clusters still produce
	# meaningful per-cycle convergence. With cycle 15-30 sec and travel up
	# to 220 px, a 600 px scatter converges visibly in ~3-5 cycles.
	var neighbor_positions: Array[Vector2] = []
	var close_count: int = 0
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != Faction.ZOMBIE:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > CLUSTER_FAR_RADIUS_PX:
			continue
		# All nearby zombies count as cluster anchors - sparse populations
		# rarely have multiple IDLE zombies within range simultaneously, so
		# the idle-only filter was killing centroid pull in exactly the
		# scenarios where it's most needed (fresh spawns, cold-start
		# clustering). Investigating / chasing zombies still register as
		# mass for centroid purposes; they just don't follow back.
		neighbor_positions.append(other.global_position)
		if d < CLUSTER_CLOSE_RADIUS_PX:
			close_count += 1
	if neighbor_positions.is_empty():
		return Vector2.ZERO
	var centroid: Vector2 = Vector2.ZERO
	for p in neighbor_positions:
		centroid += p
	centroid /= float(neighbor_positions.size())
	var to_centroid: Vector2 = centroid - global_position
	var dist: float = to_centroid.length()
	if dist < 1.0:
		return Vector2.ZERO
	var dir: Vector2 = to_centroid / dist
	# Soft cap: too many close neighbors -> push out instead of in. Tight
	# clods are fine; collapse-to-blob is not, so the cap protects against
	# 30-zombie pile-ups.
	if close_count >= CLUSTER_CROWD_THRESHOLD:
		return global_position - dir * CLUSTER_REPEL_DISTANCE_PX
	var travel: float = minf(dist * CLUSTER_TRAVEL_FRACTION, CLUSTER_TRAVEL_MAX_PX)
	return global_position + dir * travel


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
	# Phase 2.5 density gradient pull - bucketed by ZombieField's density
	# grid. Moderately dense cells pull strongly; saturated cells repel.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null:
		if zf.has_method("density_score"):
			score += zf.density_score(sample_pos)
		# Noise residue - persistent attraction to recent-activity areas.
		if zf.has_method("residue_score"):
			score += zf.residue_score(sample_pos)
	return max(0.1, score)


# Perception update at 5 Hz. Drives state transitions when targets enter
# or leave vision; LOST_TARGET fires on chase-time vision break.
func _update_perception(_delta: float) -> void:
	# CHASE: verify target still visible. Vision break -> LOST_TARGET.
	if _zombie_state == ZombieState.CHASE:
		if _target != null and is_instance_valid(_target):
			if not _can_see(_target.global_position):
				_last_known_pos = _target.global_position
				_target = null
				_zombie_state = ZombieState.LOST_TARGET
				_nav.target_position = _last_known_pos
			return
		_target = null
		_zombie_state = ZombieState.IDLE
	# ATTACK: melee range; vision break is rare and the dist check handles
	# disengagement separately. Don't re-acquire during attack.
	if _zombie_state == ZombieState.ATTACK:
		if _target != null and is_instance_valid(_target):
			return
		_target = null
		_zombie_state = ZombieState.IDLE
	# LOST_TARGET: walk to last known and look for re-acquisition. If we
	# spot any visible target en route, transition through ACQUIRING normally.
	if _zombie_state == ZombieState.LOST_TARGET:
		var maybe_visible = _find_visible_target()
		if maybe_visible != null:
			_acquiring_target = maybe_visible
			_acquisition_timer = _compute_acquisition_delay(maybe_visible.global_position)
			_zombie_state = ZombieState.ACQUIRING
		return
	# Normal flow: search for a visible target.
	var best = _find_visible_target()
	if best == null:
		if _zombie_state == ZombieState.ACQUIRING:
			_acquiring_target = null
			_zombie_state = ZombieState.IDLE
		_target = null
		return
	if _zombie_state == ZombieState.ACQUIRING and _acquiring_target == best:
		return
	var was_idle: bool = (_zombie_state == ZombieState.IDLE)
	_acquiring_target = best
	_acquisition_timer = _compute_acquisition_delay(best.global_position)
	_zombie_state = ZombieState.ACQUIRING
	# Cascade broadcast on IDLE -> ACQUIRING - other idle zombies don't
	# have vision on the target but will investigate the target's position.
	if was_idle:
		_broadcast_cascade(best.global_position, 0)


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
