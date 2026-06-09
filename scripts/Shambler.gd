extends "res://scripts/Unit.gd"

enum ZombieState { IDLE, ACQUIRING, INVESTIGATE, SEARCHING, LOST_TARGET, CHASE, ATTACK }

# Per-type perception parameters. The Zombie Substrate spec specifies these
# as per-type so Shambler / Runner / Brute can each carry their own values;
# Shambler uses the baseline. When Runner / Brute land, they override.
#
# Vision:  6 tiles = 192 px, 90° forward cone (bumped through 4 -> 5 -> 6
#          over two aggression tuning passes).
# Hearing: 22 tiles = 704 px (bumped through 12 -> 16 -> 22). Gunfire and
#          other loud noises now carry across most of the map - combat
#          anywhere draws ambient zombies from a long way off.
# Vision bumped 6 -> 9 tiles (2026-06-08 feel pass): zombies notice players
# from a more threatening range so the horde commits earlier instead of being
# nearsighted background scenery until you're 6 tiles away. Placeholder; the
# lab will sweep this with the new commitment hysteresis below.
const VISION_RANGE_TILES := 9
const VISION_RANGE_PX := VISION_RANGE_TILES * 32.0
const VISION_CONE_DEG := 90.0
const VISION_CONE_HALF_RAD := deg_to_rad(VISION_CONE_DEG * 0.5)
const VISION_EDGE_FUZZ_RAD := deg_to_rad(10.0)
const HEARING_RANGE_TILES := 22
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
const ACQUISITION_CENTER_MIN := 0.3
const ACQUISITION_CENTER_MAX := 0.6
const ACQUISITION_EDGE_MIN := 1.0
const ACQUISITION_EDGE_MAX := 1.7
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
const HEARING_PROB_MIN := 0.40
const HEARING_PROB_MAX := 0.85

# Idle head turns - zombie pivots its facing every 10-15 sec while standing
# still, simulating slow visual scanning. This is what makes peek-around-
# corner tactics nondeterministic; you don't know exactly which way the
# zombie is looking at any moment.
const HEAD_TURN_INTERVAL_MIN := 10.0
const HEAD_TURN_INTERVAL_MAX := 15.0
const FACING_PIVOT_RAD_PER_SEC := 4.0  # ~70 deg/sec, ~1.3 sec for full turn

const ATTACK_RANGE := 36.0
const LOST_TARGET_RANGE := 576.0
# Damage bumped from 8 -> 14 - second aggression tuning pass. Zombies need
# to feel actually threatening when they reach you, not just annoying.
const ATTACK_DAMAGE := 14
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
# Boids-style separation (2026-06-08 feel pass, AUDIT M2). Replaces the dead
# _cluster_bias_target() repel - this is per-frame, short-range, applied
# continuously inside _follow_navigation rather than once per wander cycle.
# Cohesion (existing wander-to-centroid) provides the long-range pull; this
# is the short-range push that prevents the pile-up and lets the horde flow
# as a spaced mass. All placeholders for the lab.
const SEPARATION_RADIUS := 28.0  # ~2 body widths (Shambler size_px = 22)
# Per-neighbor push magnitude at touching distance. Linearly weighted to 0
# at SEPARATION_RADIUS so distant neighbors don't tug. Sized to be smaller
# than Shambler move_speed (64) so cohesion still wins on the long range,
# but enough to break a pile of touching bodies apart visibly.
const SEPARATION_FORCE := 40.0

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
const MAGNETIC_RADIUS_PX := 40.0 * 32.0     # fallback radius for nearest-zombie pull (40 tiles)
const MAGNETIC_TRAVEL_FRACTION := 0.75       # travel 75% of the way (vs all the way - leaves room for jostle)
const MAGNETIC_TRAVEL_MAX_PX := 280.0        # cap per cycle so cross-map magnetic doesn't teleport
const MAGNETIC_GLOBAL_DENSITY_THRESHOLD := 3 # global densest cell must hold at least this many zombies to attract

# Home pin: each zombie's persistent attachment to a local pool. When
# near neighbors, the pin drifts to track the local centroid and
# commit strength grows. When wandering, COMMITTED zombies pull toward
# their pin (preserving their pool); UNCOMMITTED zombies pull toward
# the global densest cell (so they go find a pool).
# This is what produces multiple persistent dense spots instead of one
# mega-pile: once a zombie commits to pool A, they don't get drawn
# off to pool B even if B is bigger.
const HOME_PIN_UPDATE_INTERVAL := 2.0
const HOME_PIN_NEIGHBOR_RADIUS := 10.0 * 32.0  # 10 tiles to count as "in my pool"
const HOME_PIN_NEIGHBOR_THRESHOLD := 2          # need 2+ to update + grow commit
const HOME_PIN_DRIFT_RATE := 0.35               # how fast pin slides to new centroid
const HOME_PIN_COMMIT_GAIN := 0.18              # per update tick when neighbors present
const HOME_PIN_COMMIT_DECAY := 0.04             # per update tick when alone
const HOME_PIN_COMMIT_THRESHOLD := 0.4          # pin used as magnetic target above this
const HOME_PIN_COMMIT_MAX := 1.0

# Ambient noise: each zombie emits a low-magnitude moan periodically.
# Bypasses NoiseField entirely (so cumulative cluster moans can't
# accidentally trigger horde spawns) - directly invokes hear_noise on
# nearby zombies and deposits small residue. This is the self-
# reinforcing loop: clustered zombies moan, nearby zombies hear and
# investigate, walk in, commit, moan too. Pool grows. Hearing-only
# reach keeps the effect local: distant clusters don't poach each
# other's members.
const AMBIENT_NOISE_INTERVAL_MIN := 12.0
const AMBIENT_NOISE_INTERVAL_MAX := 22.0
const AMBIENT_NOISE_MAGNITUDE := 7.0       # just above HEARING_MIN_EFFECTIVE at close range
const AMBIENT_NOISE_RESIDUE := 4.0          # small residue deposit on each moan
const AMBIENT_NOISE_HEARING_RANGE_PX := 6.0 * 32.0  # 6-tile reach - shorter than full hearing

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

# Pass-by capture: zombies in mid-wander who enter a strongly-populated
# cell get absorbed into the cluster. The min-travel guard prevents
# self-capture during a cluster's own coordinated movement (since the
# density grid lags by 2.5 sec, the cluster's new cell isn't registered
# as dense yet - but their old cell is, so we'd otherwise trigger as
# soon as they started moving).
const PASS_BY_CAPTURE_DENSITY := 5
const PASS_BY_CAPTURE_MIN_TRAVEL := 48.0

# Phase 2.5 state cascade: when one zombie transitions IDLE -> INVESTIGATE
# or IDLE -> ACQUIRING, nearby idle zombies have a chance to follow with
# delayed propagation. Damped through three rings - primary 35%, secondary
# 20%, tertiary 10% - so the wave dies out naturally.
# (CASCADE_* removed 2026-06-08. The speculative IDLE -> ACQUIRING broadcast
# was buggy - audit M-flagged "stale pending cascades fire minutes later"
# because the pending state wasn't cleared when a zombie left IDLE. It
# also fought the new damage-driven propagation. Replaced by: the groan
# system below (damage-driven, fires only on real hits) + the proximity
# acquire (close-range 360 detection). Aggro now propagates via combat
# damage rather than via speculative "I saw a thing maybe" sight relays.)

# Damage-driven groan (2026-06-08 feel pass). When a zombie takes attack
# damage, it groans to neighbors via the ZombieField spatial index. The
# call goes DIRECT to other.hear_noise (NOT through NoiseField) so it
# doesn't feed the horde-spawn intensity ledger - that's the same shape
# the ambient moans use. Magnitude clears HEARING_RELIABLE so a groan
# reliably triggers investigate; one shot in a packed horde lights up
# the local pack. No feedback chain: hear_noise does NOT call
# take_damage (it calls investigate), so a heard groan can't re-emit a
# groan.
const GROAN_RADIUS_PX := 6.0 * 32.0   # 6 tiles; "local pack" reach
const GROAN_MAGNITUDE := 30.0         # > HEARING_RELIABLE (15) -> reliable

# Proximity acquire (2026-06-08 feel pass). 360 short-range detection
# that bypasses the vision cone and edge/range fuzz. Runs every tick in
# every active non-CHASE/non-ATTACK state so a zombie wandered or
# pulled near a unit locks on. Eligibility filter is identical to the
# cone path's: hostile faction only (faction != ZOMBIE), Walker
# exemption (load-bearing Tribal immunity mechanic - zombies NEVER
# target Walkers), tribal-aligned exemption (force-spawned zombies
# treat Tribal as ally during their 30-sec alignment window). We are
# NOT lowering who counts as a target, only how close detection works.
# Fixed acquisition delay (no randf) so it's snappy AND deterministic
# per CLAUDE.md Rule #1.
const PROXIMITY_DETECT_PX := 96.0       # 3 tiles
const PROXIMITY_ACQUISITION_DELAY := 0.05
# (CLUSTER_CROWD_THRESHOLD / TRAVEL / REPEL constants removed 2026-06-08.
# They supported the dead _cluster_bias_target() repel path — AUDIT M2.
# Per-frame separation above replaces them with a continuously-applied
# short-range push; the cluster cohesion still lives in the wander system.)
const TRIBAL_ALIGNED_COLOR := Color("5a5530")
# Force-spawned (Shaman ritual) zombies stay tribally-aligned for this many
# seconds, then revert to standard wild behavior. During the window they
# exempt all Tribal units from targeting, not just Walkers.
const TRIBAL_ALIGNMENT_DURATION := 30.0

@export var is_tribal_aligned: bool = false

var _tribal_alignment_timer: float = 0.0

# ---- Thrall system (Hunter escort, 2026-06-09) -------------------------
# A Hunter recruits up to MAX_THRALLS wild zombies as a purely DEFENSIVE
# escort (DESIGN_MASTER §7.2 living-armor redesign after the clicking
# feel-test failure — area noise pulled 50+ zombies and fired hordes).
# Thralls: follow the owning Hunter in a loose cluster, body-block between
# threats and the owner, never attack (zero DPS contribution — the escort
# raises survivability, never killing power; concentrated ranged fire can
# still shoot the Hunter past the escort, the intended Military counter).
# On the owner's death thralls revert to wild (validity-checked each tick,
# so no Hunter-side cleanup hook is needed). Loyal regardless of owner HP
# — the blood-breaks-the-mask rule applies to WILD zombies only.
const THRALL_BLOCK_DIST_PX := 28.0       # how far from the owner the block position sits, toward the threat
const THRALL_INTERCEPT_SCAN_PX := 224.0  # threat-scan radius around the owner (matches Hunter ATTACK_RANGE)
const THRALL_SCAN_INTERVAL := 0.2        # 5 Hz threat scan, mirroring the perception cadence
const THRALL_ARRIVE_EPS_PX := 4.0        # stop jittering when at the desired slot

var thrall_owner: Node2D = null          # owning Hunter; null = wild
var _pre_thrall_speed: float = -1.0      # restored on release
var _thrall_scan_timer: float = 0.0
var _thrall_threat: Node2D = null        # cached nearest threat to the owner
var _baseline_body_color: Color = Color.WHITE

var _zombie_state: int = ZombieState.IDLE
var _target = null
var _investigate_target: Vector2 = Vector2.ZERO
var _attack_cooldown := 0.0
var _perception_timer := 0.0
# Cached result of _find_proximity_target. The scan runs only on the
# perception tick (5 Hz, see _physics_process); the state-transition
# check below reads the cached value every physics tick. Pre-throttle
# this scan ran at 60 Hz and was the dominant cost in the late-game
# perf cliff (~250 zombies x 60 Hz x ~250-unit iteration). Cleared on
# every perception tick so stale values can't reacquire dead targets.
var _proximity_cached: Node = null
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
# Where we started our current wander leg, for pass-by capture distance.
var _wander_start_pos: Vector2 = Vector2.ZERO
# Home pin: persistent attachment to local pool. Vector2.ZERO until first
# commitment forms. Strength 0..1 - we use the pin as magnetic target
# only when strength >= HOME_PIN_COMMIT_THRESHOLD.
var _home_pin: Vector2 = Vector2.ZERO
var _home_pin_commit: float = 0.0
var _home_pin_timer: float = 0.0
var _ambient_noise_timer: float = 0.0
# Cascade pending state - level we joined at (-1 = no pending), the
# stimulus we'll investigate when the delay timer fires, and the timer.
# (_pending_cascade_* removed 2026-06-08 - see comment on CASCADE_* above.)

# Preallocated query objects for _find_visible_target. Reusing these avoids
# the ~1100 allocations/sec a per-zombie per-tick `.new()` would cost at
# 200+ population.
var _vision_shape: CircleShape2D = null
var _vision_query: PhysicsShapeQueryParameters2D = null

# Per-zombie chase offset. Each zombie picks a stable offset around its target
# based on instance_id so that multiple zombies converging on the same target
# spread out into a loose ring instead of piling onto a single point. Read
# once on _ready; never changes per zombie. Result: clusters "flow" toward
# a target instead of shuffling-and-bumping into each other.
var _chase_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	# Group registration (2026-06-09): the "zombies" group did NOT exist
	# before this line — Shambler was only in "units" (scene-set). Two
	# consumers depended on it silently failing: SimChecksum was hashing an
	# empty zombie list (zombie positions were invisible to the determinism
	# CI), and the thrall threat-scan would never see wild zombies.
	add_to_group("zombies")
	# Vision query setup - one CircleShape2D + PhysicsShapeQueryParameters2D
	# per zombie, reused on every perception tick. H6 layer split: non-zombie
	# units join layer 3 in Unit._ready, so mask = 4 (layer 3 only) means the
	# 16-slot intersect_shape cap is consumed exclusively by real targets,
	# not by neighboring zombies in a cluster. collide_with_areas false so
	# Projectile Area2Ds don't appear in the query results.
	_vision_shape = CircleShape2D.new()
	_vision_shape.radius = VISION_RANGE_PX
	_vision_query = PhysicsShapeQueryParameters2D.new()
	_vision_query.shape = _vision_shape
	_vision_query.collision_mask = 4
	_vision_query.collide_with_bodies = true
	_vision_query.collide_with_areas = false
	# Deterministic per-zombie chase offset. instance_id is unique, so each
	# zombie picks a stable point on a small ring around any chase target.
	# Radius 14-30 px keeps them within ATTACK_RANGE (36 px) but spread.
	var id_hash: int = get_instance_id()
	var angle: float = float(id_hash % 360) * deg_to_rad(1.0)
	var radius: float = 14.0 + float(id_hash % 16)
	_chase_offset = Vector2.from_angle(angle) * radius
	_wander_timer = SimRng.randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
	_head_turn_timer = SimRng.randf_range(HEAD_TURN_INTERVAL_MIN, HEAD_TURN_INTERVAL_MAX)
	_ambient_noise_timer = SimRng.randf_range(AMBIENT_NOISE_INTERVAL_MIN, AMBIENT_NOISE_INTERVAL_MAX)
	# Initial facing: random cardinal-ish so spawned zombies aren't all
	# looking the same direction. Faces "south" by default before this.
	_facing_angle = SimRng.randf() * TAU
	_desired_facing_angle = _facing_angle
	facing_dir = Vector2.from_angle(_facing_angle)
	# Preserve the original body color before the tribal-aligned override so
	# we can revert to it when the 30-sec timer expires.
	_baseline_body_color = body_color
	if is_tribal_aligned:
		body_color = TRIBAL_ALIGNED_COLOR
		_tribal_alignment_timer = TRIBAL_ALIGNMENT_DURATION
		queue_redraw()
	# Wire up the v1 Pixellab sprite art if the asset tree is present. No-ops
	# gracefully when frames are missing (use_sprite stays false and the
	# procedural _draw branch above keeps the silhouette visible).
	_init_shambler_sprite()


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

	# Procedural body/head/facing-tick are skipped when use_sprite is true
	# (the AnimatedSprite2D child handles the silhouette + facing read).
	# Shadow + selection ring + HP bar stay because the sprite art doesn't
	# carry them.
	if not use_sprite:
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
	# (cascade_join_level param removed 2026-06-08 with the cascade system.)
	# Thralls ignore noise — they hold their escort slot (purely defensive,
	# never wander off toward stimuli; the owner is the only anchor).
	if _is_thralled():
		return
	if _zombie_state == ZombieState.CHASE or _zombie_state == ZombieState.ATTACK:
		return
	if _zombie_state == ZombieState.LOST_TARGET:
		return
	# ACQUIRING guard (AUDIT M4, 2026-06-08): a mid-acquisition zombie has
	# already locked on to a visible target and is counting down the
	# acquisition delay; an ambient neighbor moan fires every 3-10s and
	# would otherwise yank this zombie off the real target before it
	# could commit to CHASE.
	if _zombie_state == ZombieState.ACQUIRING:
		return
	if (_zombie_state == ZombieState.INVESTIGATE or _zombie_state == ZombieState.SEARCHING) and \
		_investigate_target.distance_to(world_pos) < PERSIST_RADIUS_PX:
		# Fresh noise inside PERSIST_RADIUS - the user is moving and
		# shooting; re-point at the new spot instead of milling at the
		# stale one (2026-06-08 fix). Pre-fix the early-return here
		# locked the investigation onto the first noise location and a
		# moving shooter could pull the horde without it ever following.
		_investigate_target = world_pos
		if _zombie_state == ZombieState.SEARCHING:
			# Shooter moved while we were wandering near the stale spot -
			# go back to walking toward the new noise position. The next
			# arrival re-enters SEARCHING at the new location.
			_zombie_state = ZombieState.INVESTIGATE
			_wandering = false
		_nav.target_position = world_pos
		_set_desired_facing(world_pos)
		return
	_investigate_target = world_pos
	_zombie_state = ZombieState.INVESTIGATE
	_wandering = false
	_set_desired_facing(world_pos)
	_nav.target_position = world_pos


# (on_cascade / _broadcast_cascade removed 2026-06-08. Replaced by damage-
# driven groan + proximity acquire above; see CASCADE_* comment.)


# Called by NoiseField for every active emitter. Zombie filters by its own
# per-type hearing range and noise attenuation; triggers investigate() if
# the effective magnitude clears the threshold.
func hear_noise(noise_pos: Vector2, magnitude: float, distance: float) -> void:
	# Thralls are deaf to noise — escort slot only (see investigate()).
	if _is_thralled():
		return
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


# Override of Unit._follow_navigation that injects a short-range boids
# separation force between desired-velocity and move_and_slide. The feel
# fix (2026-06-08): pre-fix zombies all A*-pathed to the same point and
# collided into a slow-stagger pile because nothing pushed them apart at
# touching distance. This is the standard third boids component
# (alignment + cohesion + separation); the existing wander-to-centroid
# is the cohesion, this is the missing separation.
#
# Deterministic: reads the ZombieField spatial cell index (CLAUDE.md
# Rule #3), no transcendentals, sum of normalized push vectors is
# associative so iteration order doesn't matter (Rule #4 satisfied).
# Stays compatible with the avoidance_enabled=false path (no Godot RVO -
# that would be nondeterministic AND gridlocks).
func _follow_navigation() -> bool:
	# Two parallel bodies to keep the timing wraps' overhead out of the hot
	# path when DIAG_SHAMBLER_TIMING is off (the default). They are kept in
	# sync; if you touch one, touch the other.
	if PerfProbe.DIAG_SHAMBLER_TIMING:
		var t_nav_us: int = Time.get_ticks_usec()
		if _nav.is_navigation_finished():
			velocity = Vector2.ZERO
			PerfProbe.shambler_nav_us += Time.get_ticks_usec() - t_nav_us
			return false
		var next_pos_t := _nav.get_next_path_position()
		var to_next_t := next_pos_t - global_position
		var desired_t: Vector2 = to_next_t.normalized() * get_effective_move_speed()
		var t_sep_us: int = Time.get_ticks_usec()
		desired_t += _compute_separation()
		PerfProbe.shambler_sep_us += Time.get_ticks_usec() - t_sep_us
		if _nav.avoidance_enabled:
			_nav.set_velocity(desired_t)
		else:
			velocity = desired_t
			move_and_slide()
		PerfProbe.shambler_nav_us += Time.get_ticks_usec() - t_nav_us
		return true
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return false
	var next_pos := _nav.get_next_path_position()
	var to_next := next_pos - global_position
	var desired: Vector2 = to_next.normalized() * get_effective_move_speed()
	desired += _compute_separation()
	if _nav.avoidance_enabled:
		_nav.set_velocity(desired)
	else:
		velocity = desired
		move_and_slide()
	return true


func _compute_separation() -> Vector2:
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf == null or not zf.has_method("get_zombies_within_radius"):
		return Vector2.ZERO
	var push: Vector2 = Vector2.ZERO
	for other in zf.get_zombies_within_radius(global_position, SEPARATION_RADIUS):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = global_position - other.global_position
		var d_sq: float = away.length_squared()
		# Skip exact-overlap (degenerate; from spawn-stack frames) and any
		# neighbor at or beyond the cutoff radius (the cell sweep can return
		# them due to cell-padding).
		if d_sq < 0.01 or d_sq > SEPARATION_RADIUS * SEPARATION_RADIUS:
			continue
		var d: float = sqrt(d_sq)
		# Linear taper: weight = 1.0 at touching, 0.0 at SEPARATION_RADIUS.
		# Keeps the force short-range so it does NOT fight the longer-range
		# wander-cohesion that pulls the horde together.
		var weight: float = 1.0 - (d / SEPARATION_RADIUS)
		push += (away / d) * weight
	return push * SEPARATION_FORCE


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


# ---- Thrall behavior ----------------------------------------------------


func make_thrall(owner: Node2D) -> bool:
	# Called by the recruiting Hunter. Returns false if already owned.
	if thrall_owner != null or owner == null or not is_instance_valid(owner):
		return false
	thrall_owner = owner
	_pre_thrall_speed = move_speed
	# Speed-match the owner so the escort keeps pace (Hunters move faster
	# than Shamblers; an escort that lags behind is no escort).
	if "move_speed" in owner:
		move_speed = owner.move_speed
	# Drop whatever the wild brain was doing — the slot is the only goal.
	_zombie_state = ZombieState.IDLE
	_target = null
	_wandering = false
	return true


func release_thrall() -> void:
	# Revert to wild: clear the assignment, restore speed, and let the
	# normal behavior tree resume next tick (it re-runs wild aggro
	# naturally — a freed thrall near a loud battle will investigate it,
	# the same dynamic as the Caller/Shaman control rule in §7.2).
	thrall_owner = null
	_thrall_threat = null
	if _pre_thrall_speed > 0.0:
		move_speed = _pre_thrall_speed
		_pre_thrall_speed = -1.0


func _is_thralled() -> bool:
	return thrall_owner != null and is_instance_valid(thrall_owner)


func _tick_thrall(delta: float) -> void:
	# 5 Hz threat scan around the OWNER (not the thrall) — the escort exists
	# to protect the Hunter, so threats are measured from his position.
	_thrall_scan_timer -= delta
	if _thrall_scan_timer <= 0.0:
		_thrall_scan_timer = THRALL_SCAN_INTERVAL
		_thrall_threat = _find_owner_threat()
	# Desired slot: with a live threat, body-block on the segment owner ->
	# threat at THRALL_BLOCK_DIST from the owner (absorb what's meant for
	# him). Without one, hold a loose ring slot via the per-zombie stable
	# _chase_offset so the escort doesn't stack into one pixel.
	var slot: Vector2
	if _thrall_threat != null and is_instance_valid(_thrall_threat):
		var to_threat: Vector2 = _thrall_threat.global_position - thrall_owner.global_position
		if to_threat.length_squared() > 1.0:
			slot = thrall_owner.global_position + to_threat.normalized() * THRALL_BLOCK_DIST_PX + _chase_offset * 0.5
		else:
			slot = thrall_owner.global_position + _chase_offset
	else:
		slot = thrall_owner.global_position + _chase_offset
	var to_slot: Vector2 = slot - global_position
	if to_slot.length() <= THRALL_ARRIVE_EPS_PX:
		velocity = Vector2.ZERO
	else:
		velocity = to_slot.normalized() * move_speed
		_set_desired_facing(slot)
	move_and_slide()


func _find_owner_threat() -> Node2D:
	# Nearest hostile to the owner within THRALL_INTERCEPT_SCAN_PX.
	# Deterministic: strict nearest-by-distance, first-seen wins exact ties
	# (group order — acceptable until spawn-ordinal ids land; ties are
	# measure-zero in practice). Uses GameState.is_hostile so the scan
	# covers both enemy humans and WILD zombies — a wounded owner's escort
	# blocks the wild dead coming for him too. Thralled zombies (any
	# owner's) are skipped: escorts don't block each other.
	var best: Node2D = null
	var best_dist: float = THRALL_INTERCEPT_SCAN_PX
	var candidates: Array = get_tree().get_nodes_in_group("player_units")
	candidates.append_array(get_tree().get_nodes_in_group("ai_units"))
	candidates.append_array(get_tree().get_nodes_in_group("zombies"))
	for u in candidates:
		if u == self or u == null or not is_instance_valid(u):
			continue
		if "thrall_owner" in u and u.thrall_owner != null:
			continue
		if not GameState.is_hostile(thrall_owner, u):
			continue
		var d: float = thrall_owner.global_position.distance_to(u.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best


func _physics_process(delta: float) -> void:
	# Diagnostic timing (2026-06-08). Gated by PerfProbe.DIAG_SHAMBLER_TIMING
	# (default off). The wraps below + the helper split add up to ~120k
	# Time.get_ticks_usec() calls/sec at 250 zombies x time_scale 8, so
	# leaving them live skewed the very measurement they were taking.
	# Helper split is kept either way so scattered `return` paths in the
	# match block don't skip the post-tick accumulation when timing is on.
	if PerfProbe.DIAG_SHAMBLER_TIMING:
		var t_start_us: int = Time.get_ticks_usec()
		_physics_tick(delta)
		PerfProbe.shambler_total_us += Time.get_ticks_usec() - t_start_us
		PerfProbe.shambler_ticks += 1
	else:
		_physics_tick(delta)


func _physics_tick(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_shambler_sprite_animation()
	_tick_facing(delta)
	# Thrall escort path replaces the whole wild behavior tree (no wander,
	# no perception, no attack — purely defensive body-blocking). Owner
	# validity is checked every tick: a dead Hunter's thralls revert to
	# wild here with no Hunter-side cleanup needed.
	if thrall_owner != null:
		if not is_instance_valid(thrall_owner):
			release_thrall()
		else:
			_tick_thrall(delta)
			return
	# Home pin tracking runs regardless of state - even chasing/investigating
	# zombies should keep their pin updated when they're near neighbors, so
	# that after they finish the chase they return to the same pool.
	_home_pin_timer -= delta
	if _home_pin_timer <= 0.0:
		_home_pin_timer = HOME_PIN_UPDATE_INTERVAL
		_update_home_pin()
	# Ambient moan: emit periodically to attract nearby zombies and
	# deposit residue. Bypasses NoiseField so no horde spawn risk.
	_ambient_noise_timer -= delta
	if _ambient_noise_timer <= 0.0:
		_ambient_noise_timer = randf_range(AMBIENT_NOISE_INTERVAL_MIN, AMBIENT_NOISE_INTERVAL_MAX)
		_emit_ambient_noise()
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
		if PerfProbe.DIAG_SHAMBLER_TIMING:
			var t_perc_us: int = Time.get_ticks_usec()
			_update_perception(delta)
			PerfProbe.shambler_perc_us += Time.get_ticks_usec() - t_perc_us
		else:
			_update_perception(delta)
		if _target != null and _zombie_state == ZombieState.CHASE:
			_nav.target_position = _target.global_position + _chase_offset
		# Proximity acquire scan throttled to the perception tick on
		# 2026-06-08 to fix the late-game cliff. Pre-throttle, this scan
		# (iterates get_nodes_in_group("units")) ran every physics tick
		# in every non-CHASE/non-ATTACK zombie - at ~250 zombies that was
		# ~4M iterations/sec and dropped fps to <1 by t=90s. Now it runs
		# at 5 Hz; the cached result is consumed every tick below for the
		# cheap state transition. Determinism is preserved (delta
		# accumulator on the physics tick, no wall-clock).
		if _zombie_state != ZombieState.CHASE and _zombie_state != ZombieState.ATTACK:
			if PerfProbe.DIAG_SHAMBLER_TIMING:
				var t_prox_us: int = Time.get_ticks_usec()
				_proximity_cached = _find_proximity_target()
				PerfProbe.shambler_proxim_us += Time.get_ticks_usec() - t_prox_us
			else:
				_proximity_cached = _find_proximity_target()
		else:
			_proximity_cached = null

	# Proximity acquire transition (2026-06-08). Consumes the cached scan
	# from the perception block above. The state change is cheap (no
	# iteration), so it stays on the 60 Hz physics tick - this preserves
	# the snappy "walk into a horde, get grabbed" feel even though the
	# scan only refreshes 5x/sec. Eligibility filter (hostile faction,
	# Walker exempt, tribal-aligned Tribal exempt) is enforced inside
	# _find_proximity_target itself. Fixed-delay acquisition (no RNG per
	# Determinism Rule #1).
	if _zombie_state != ZombieState.CHASE and _zombie_state != ZombieState.ATTACK:
		var prox = _proximity_cached
		if prox != null and is_instance_valid(prox) and prox != _acquiring_target:
			_acquiring_target = prox
			_acquisition_timer = PROXIMITY_ACQUISITION_DELAY
			_zombie_state = ZombieState.ACQUIRING

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
				_nav.target_position = _target.global_position + _chase_offset
		ZombieState.INVESTIGATE:
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position + _chase_offset
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
				_nav.target_position = _target.global_position + _chase_offset
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
				# Hold the lunge/bite pose so the sprite animation finishes the
				# action even after the cooldown timer is set for the next bite.
				_attack_anim_timer = ATTACK_ANIM_HOLD


func _tick_wander(delta: float) -> void:
	if _wandering:
		# Pass-by capture: if we've traveled far enough that we're not
		# moving within our own cluster's residue, and we're now standing
		# in a strongly-populated cell, abandon the wander and idle here.
		# Captain check on the next tick will absorb us into the cluster.
		if global_position.distance_to(_wander_start_pos) > PASS_BY_CAPTURE_MIN_TRAVEL:
			if _zombie_field_density_here() >= PASS_BY_CAPTURE_DENSITY:
				_wandering = false
				_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
				velocity = Vector2.ZERO
				_captain_check_timer = 0.0  # force re-election next idle frame
				return
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
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombies_within_radius"):
		for other in zf.get_zombies_within_radius(global_position, COHESION_RADIUS_PX):
			if other == self:
				continue
			if other.get_instance_id() < my_id:
				_is_captain = false
				return
		_is_captain = true
		return
	# Fallback if ZombieField not present.
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != GameState.Faction.ZOMBIE:
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
	# Magnetic always fires now (no probability gate). All zombies are
	# attracted to other zombies as a default behavior, not a probabilistic
	# bias. Targets the densest cell on the entire map; falls back to
	# nearest individual zombie within MAGNETIC_RADIUS if no significant
	# cluster exists.
	if target == Vector2.ZERO:
		target = _find_magnetic_target()
	if target == Vector2.ZERO:
		var direction: Vector2 = _pick_wander_direction()
		target = global_position + direction * WANDER_RADIUS
	target.x = clamp(target.x, 50.0, 6094.0)
	target.y = clamp(target.y, 50.0, 6094.0)
	_wander_target = target
	_wandering = true
	_wander_start_pos = global_position
	_nav.target_position = _wander_target
	_propagate_wander_to_cluster()


func _zombie_field_density_here() -> int:
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf == null or not zf.has_method("get_density_at"):
		return 0
	return zf.get_density_at(global_position)


func take_damage(amount: int, attacker = null) -> void:
	# Override of Unit.take_damage to emit the damage-driven groan
	# (2026-06-08 feel pass). Behavior of the damage application is
	# unchanged; we just react to it here.
	var hp_before: int = current_hp
	super.take_damage(amount, attacker)
	# Groan only fires on actual attack damage AND only while still alive.
	# The guard against an infinite chain is that hear_noise on the
	# receiving side calls investigate(), not take_damage - a heard groan
	# never causes another groan.
	if amount > 0 and current_hp > 0 and current_hp != hp_before:
		_emit_groan()


func _emit_groan() -> void:
	# Direct hear_noise to nearby zombies via the spatial index. Same
	# direct-call path the ambient moans use so this does NOT feed
	# NoiseField - if it did, combat groans would start triggering
	# horde-spawns and the system would snowball. Magnitude clears
	# HEARING_RELIABLE so a groan reliably converts to investigate.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf == null or not zf.has_method("get_zombies_within_radius"):
		return
	for other in zf.get_zombies_within_radius(global_position, GROAN_RADIUS_PX):
		if other == self or other == null or not is_instance_valid(other):
			continue
		if not other.has_method("hear_noise"):
			continue
		var d: float = global_position.distance_to(other.global_position)
		other.hear_noise(global_position, GROAN_MAGNITUDE, d)


func _emit_ambient_noise() -> void:
	# Deposit small residue for long-term attraction trail.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("deposit_residue"):
		zf.deposit_residue(global_position, AMBIENT_NOISE_RESIDUE)
	# Direct hear_noise to nearby zombies via the spatial index. Bypasses
	# NoiseField so cumulative cluster moans can't false-trigger hordes.
	if zf != null and zf.has_method("get_zombies_within_radius"):
		for other in zf.get_zombies_within_radius(global_position, AMBIENT_NOISE_HEARING_RANGE_PX):
			if other == self or not other.has_method("hear_noise"):
				continue
			var d: float = global_position.distance_to(other.global_position)
			other.hear_noise(global_position, AMBIENT_NOISE_MAGNITUDE, d)
		return
	# Fallback - rare, ZombieField always present in normal scenes.
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or not is_instance_valid(other):
			continue
		if other.faction != GameState.Faction.ZOMBIE:
			continue
		if not other.has_method("hear_noise"):
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > AMBIENT_NOISE_HEARING_RANGE_PX:
			continue
		other.hear_noise(global_position, AMBIENT_NOISE_MAGNITUDE, d)


func _update_home_pin() -> void:
	# Scan zombies within HOME_PIN_NEIGHBOR_RADIUS. If we have enough
	# neighbors, drift our pin toward their centroid and grow commit.
	# If alone, decay commit (slow loss of pool loyalty).
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombies_within_radius"):
		for other in zf.get_zombies_within_radius(global_position, HOME_PIN_NEIGHBOR_RADIUS):
			if other == self:
				continue
			sum += other.global_position
			count += 1
	else:
		for other in get_tree().get_nodes_in_group("units"):
			if other == self or not is_instance_valid(other):
				continue
			if other.faction != GameState.Faction.ZOMBIE:
				continue
			if global_position.distance_to(other.global_position) > HOME_PIN_NEIGHBOR_RADIUS:
				continue
			sum += other.global_position
			count += 1
	if count >= HOME_PIN_NEIGHBOR_THRESHOLD:
		var centroid: Vector2 = sum / float(count)
		if _home_pin == Vector2.ZERO:
			_home_pin = centroid
		else:
			_home_pin = _home_pin.lerp(centroid, HOME_PIN_DRIFT_RATE)
		_home_pin_commit = minf(_home_pin_commit + HOME_PIN_COMMIT_GAIN, HOME_PIN_COMMIT_MAX)
	else:
		_home_pin_commit = maxf(_home_pin_commit - HOME_PIN_COMMIT_DECAY, 0.0)
		if _home_pin_commit <= 0.001:
			_home_pin = Vector2.ZERO


func _find_magnetic_target() -> Vector2:
	# Three-tier magnetic attraction, decided by commitment:
	#   1. Committed (home pin > threshold): target our pin. Preserves
	#      pool identity - we don't get drawn off to a bigger pile
	#      somewhere else. This is what allows MULTIPLE persistent
	#      dense spots to form on the map.
	#   2. Uncommitted + global pile exists: target densest cell on map.
	#      Lone wanderers seek out the largest pool to join.
	#   3. Fallback: nearest individual zombie within MAGNETIC_RADIUS_PX.
	#      Used cold-start when no real pile exists yet.
	if _home_pin_commit >= HOME_PIN_COMMIT_THRESHOLD and _home_pin != Vector2.ZERO:
		var to_pin: Vector2 = _home_pin - global_position
		if to_pin.length_squared() > (32.0 * 32.0):
			var travel_p: float = minf(to_pin.length() * MAGNETIC_TRAVEL_FRACTION, MAGNETIC_TRAVEL_MAX_PX)
			return global_position + to_pin.normalized() * travel_p
		# Already at our pin - fall through to nearest-zombie nudge so
		# we don't return our own position as target.
	else:
		var zf = get_tree().get_first_node_in_group("zombie_field")
		if zf != null and zf.has_method("get_densest_cell_center"):
			var densest_count: int = zf.get_densest_cell_count()
			if densest_count >= MAGNETIC_GLOBAL_DENSITY_THRESHOLD:
				var center: Vector2 = zf.get_densest_cell_center()
				var to_center: Vector2 = center - global_position
				if to_center.length_squared() > (64.0 * 64.0):
					var travel_g: float = minf(to_center.length() * MAGNETIC_TRAVEL_FRACTION, MAGNETIC_TRAVEL_MAX_PX)
					return global_position + to_center.normalized() * travel_g
	# Fallback: nearest individual zombie. Use ZombieField spatial index.
	var nearest = null
	var nearest_dist: float = MAGNETIC_RADIUS_PX
	var zf2 = get_tree().get_first_node_in_group("zombie_field")
	if zf2 != null and zf2.has_method("get_zombies_within_radius"):
		for other in zf2.get_zombies_within_radius(global_position, MAGNETIC_RADIUS_PX):
			if other == self:
				continue
			var d: float = global_position.distance_to(other.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = other
	else:
		for other in get_tree().get_nodes_in_group("units"):
			if other == self or not is_instance_valid(other):
				continue
			if other.faction != GameState.Faction.ZOMBIE:
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
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombies_within_radius"):
		for other in zf.get_zombies_within_radius(global_position, COHESION_RADIUS_PX):
			if other == self:
				continue
			nearby_count += 1
			if other.has_method("follow_leader_wander"):
				nearby_followers.append(other)
	else:
		for other in get_tree().get_nodes_in_group("units"):
			if other == self or not is_instance_valid(other):
				continue
			if other.faction != GameState.Faction.ZOMBIE:
				continue
			var d: float = global_position.distance_to(other.global_position)
			if d > COHESION_RADIUS_PX:
				continue
			nearby_count += 1
			if other.has_method("follow_leader_wander"):
				nearby_followers.append(other)
	if nearby_count < COHESION_NEIGHBOR_THRESHOLD:
		return
	# Push ALL followers, no random skip. The previous 5% per-cycle leak
	# was what slowly fractured large clusters across many cycles.
	for f in nearby_followers:
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
	_wander_start_pos = global_position
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
	# Use ZombieField spatial index instead of scanning the full units group.
	var leader = null
	var leader_dist: float = INF
	var nearby_count: int = 0
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombies_within_radius"):
		for other in zf.get_zombies_within_radius(global_position, COHESION_RADIUS_PX):
			if other == self:
				continue
			nearby_count += 1
			if not other.has_method("get_active_wander_target"):
				continue
			var t: Vector2 = other.get_active_wander_target()
			if t == Vector2.ZERO:
				continue
			var d: float = global_position.distance_to(other.global_position)
			if d < leader_dist:
				leader_dist = d
				leader = other
	else:
		for other in get_tree().get_nodes_in_group("units"):
			if other == self or not is_instance_valid(other):
				continue
			if other.faction != GameState.Faction.ZOMBIE:
				continue
			var d2: float = global_position.distance_to(other.global_position)
			if d2 > COHESION_RADIUS_PX:
				continue
			nearby_count += 1
			if not other.has_method("get_active_wander_target"):
				continue
			var t2: Vector2 = other.get_active_wander_target()
			if t2 == Vector2.ZERO:
				continue
			if d2 < leader_dist:
				leader_dist = d2
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


# (Removed 2026-06-08, AUDIT M2: _cluster_bias_target was dead code - zero
# callers. It was once-per-wander-cycle centroid bias with a hard repel at
# 14 neighbors; the role is now fulfilled by per-frame _compute_separation
# above, which is continuous + short-range and integrates cleanly with
# _follow_navigation rather than requiring a separate wander target. The
# wander-cohesion is intact - that lives in _pick_wander_direction below.)


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
	# CHASE: hysteresis-based retention (AUDIT M3, fix 2026-06-08). Pre-fix
	# this re-ran _can_see every perception tick, which includes the same
	# stochastic detection fuzz as acquisition - zombies thrashed out of
	# CHASE on ~60% of ticks. Once committed, only physical distance from
	# the target should break the chase, not perception noise. Drop only
	# when the target is beyond LOST_TARGET_RANGE - the dead constant the
	# audit flagged as the intended hysteresis lever.
	if _zombie_state == ZombieState.CHASE:
		if _target != null and is_instance_valid(_target):
			var d_chase: float = global_position.distance_to(_target.global_position)
			if d_chase > LOST_TARGET_RANGE:
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
	_acquiring_target = best
	_acquisition_timer = _compute_acquisition_delay(best.global_position)
	_zombie_state = ZombieState.ACQUIRING
	# (Cascade broadcast removed 2026-06-08 - replaced by damage-driven
	# groan + proximity acquire. The speculative sight-relay was buggy
	# and double-counted with the new propagation paths.)


# Proximity acquire (2026-06-08). 360 deg short-range detection that bypasses
# the vision cone + edge/range fuzz so a unit standing right next to the
# zombie is reliably noticed - the "walking into a packed horde and they
# don't react" case the feel-test caught.
#
# Eligibility (the same target filter the cone path enforces, written out
# explicitly here so the rules don't depend on cross-reading another
# function):
#   - Skip self and invalid nodes.
#   - Skip nodes without a faction property (buildings, etc.).
#   - Skip ZOMBIE faction (no zombie-on-zombie targeting).
#   - Skip the "walkers" group: Walkers are load-bearing for Tribal's
#     zombie-immunity identity; zombies NEVER target them.
#   - Skip TRIBAL faction while this zombie is tribal-aligned (the
#     30-sec force-spawn alliance window).
#
# Returns nearest valid target within PROXIMITY_DETECT_PX, or null. LOS
# check kept so walls still block (a zombie in the next room shouldn't
# smell through a wall). No RNG.
func _find_proximity_target():
	# 2026-06-08 perf fix: scan player_units + ai_units instead of the full
	# "units" group. Diagnostic showed this scan was 62% of Shambler tick
	# time at 197 zombies because every zombie was iterating all 250 units
	# (including 247 fellow zombies) at 5 Hz. The two team groups together
	# hold only the ~10-20 non-zombie units that could ever be a target -
	# 250 zombies are filtered at the group lookup instead of one-by-one.
	# Iteration order is preserved (player_units first, ai_units second)
	# so determinism is unchanged for any same-faction-but-opposite-team
	# corner case the original code might have surfaced.
	var best = null
	var best_dist: float = PROXIMITY_DETECT_PX
	var candidates: Array = get_tree().get_nodes_in_group("player_units")
	candidates.append_array(get_tree().get_nodes_in_group("ai_units"))
	for u in candidates:
		if u == self or u == null or not is_instance_valid(u):
			continue
		if not ("faction" in u):
			continue
		if u.faction == GameState.Faction.ZOMBIE:
			continue
		if u.is_in_group("walkers"):
			continue
		if is_tribal_aligned and u.faction == GameState.Faction.TRIBAL:
			continue
		# "Blood breaks the mask" — DESIGN_MASTER §7.2. A HEALTHY Tribal unit
		# is invisible to zombie targeting; a wounded Tribal unit reads as
		# prey. v1 uses an HP threshold as the proxy for "bleeding" — the
		# full blood/scent-trail version lands with the scent system later.
		# Walkers stay unconditionally immune above via the walkers-group
		# check (the bone-painted scavenger; they always wear the mask).
		if _tribal_mask_intact(u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d > best_dist:
			continue
		if not _has_los(u.global_position):
			continue
		best_dist = d
		best = u
	return best


# v1 conditional immunity per DESIGN_MASTER §7.2 ("blood breaks the mask").
# A Tribal unit is exempt from zombie targeting while its HP is at or above
# this fraction of its max. Below the threshold the mask cracks, the zombie
# sees them, and they get pursued. 0.5 = "any heavy commit exposes you" —
# tunable in the lab. Walker (in "walkers" group) is checked separately
# upstream and stays unconditionally immune.
const TRIBAL_MASK_HP_THRESHOLD := 0.5


func _tribal_mask_intact(u) -> bool:
	# Returns true iff the target is a healthy Tribal unit whose mask is
	# still intact (above the HP threshold). Defensive nulls so an
	# unfinished subclass without hp fields can't crash perception.
	if u == null or not is_instance_valid(u):
		return false
	if not "faction" in u or u.faction != GameState.Faction.TRIBAL:
		return false
	if not "current_hp" in u or not "max_hp" in u or u.max_hp <= 0:
		return false
	return float(u.current_hp) >= float(u.max_hp) * TRIBAL_MASK_HP_THRESHOLD


func _find_visible_target():
	# Per spec: only Walkers are exempt from all zombie targeting. Tribal
	# Hunters and Shamans are detected normally. Tribally-aligned zombies
	# (force-spawned) exempt all Tribal during their 30-sec alignment.
	#
	# Uses Godot's physics broadphase via intersect_shape with a circle of
	# VISION_RANGE_PX radius. Cost: O(units-within-vision), typically 0-5,
	# instead of O(all-units) which at 200+ zombie population was the second-
	# biggest perf hit after the projectile friendly-fire loop.
	var space := get_world_2d().direct_space_state
	_vision_query.transform = Transform2D(0.0, global_position)
	var hits: Array = space.intersect_shape(_vision_query, 16)
	var best = null
	var best_dist: float = VISION_RANGE_PX
	for h in hits:
		var u = h.get("collider", null)
		if u == self or u == null or not is_instance_valid(u):
			continue
		if not ("faction" in u):
			continue
		if u.faction == GameState.Faction.ZOMBIE:
			continue
		# Walkers are always invisible to zombie targeting - the load-bearing
		# Tribal identity mechanic.
		if u.is_in_group("walkers"):
			continue
		# Force-spawned zombies treat all Tribal as ally during the 30-sec
		# alignment window.
		if is_tribal_aligned and u.faction == GameState.Faction.TRIBAL:
			continue
		# "Blood breaks the mask" — healthy Tribal are invisible at long range
		# too. See proximity branch above for the rationale.
		if _tribal_mask_intact(u):
			continue
		if not _can_see(u.global_position):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	return best


# ---- Sprite system (DESIGN_MASTER §5; v1 Pixellab art) -----------------
#
# Mirrors CombatUnit's sprite loader but lives here because Shambler
# extends Unit directly (not CombatUnit). v2 may promote this whole
# block up to Unit.gd so the duplication is removed.
#
# RENDER ONLY. The atan2 + rad_to_deg inside _world_facing_to_sprite_dir
# are sanctioned render-side transcendentals per CLAUDE.md - sim state
# never reads back from the sprite frame chosen.

const SPRITE_ROOT := "res://assets/sprites/units/zombies/shambler/"
const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

# Action -> animation-fps. attack is fast and fairly punchy (lunge/bite
# read in 0.4s); death is slower-fall.
const SPRITE_ANIM_SPEEDS := {"idle": 4.0, "walk": 10.0, "attack": 14.0, "death": 8.0}
const SPRITE_ANIM_LOOPS := {"idle": true, "walk": true, "attack": false, "death": false}

# Attack-pose hold so the lunge frames stay visible past the actual
# 1s attack-cooldown. Decremented in _physics_process.
const ATTACK_ANIM_HOLD := 0.45
var _attack_anim_timer: float = 0.0


func _build_shambler_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	for action in ["idle", "walk", "attack", "death"]:
		for dir in SPRITE_DIRECTIONS:
			var anim_name := "%s_%s" % [action, dir]
			var added_any := false
			var i := 0
			while true:
				var frame_path := "%s%s/%s/%d.png" % [SPRITE_ROOT, action, dir, i]
				if not ResourceLoader.exists(frame_path):
					break
				if not added_any:
					sf.add_animation(anim_name)
					sf.set_animation_speed(anim_name, SPRITE_ANIM_SPEEDS[action])
					sf.set_animation_loop(anim_name, SPRITE_ANIM_LOOPS[action])
					added_any = true
				sf.add_frame(anim_name, load(frame_path))
				i += 1
	return sf


func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


func _init_shambler_sprite() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frames := _build_shambler_sprite_frames()
	if frames == null or frames.get_animation_names().is_empty():
		return
	sprite.sprite_frames = frames
	use_sprite = true
	sprite.play(&"idle_south")


# Pick action + direction from the zombie state machine. Mirrors the
# CombatUnit version's structure but reads from _zombie_state /
# _attack_anim_timer instead of current_command / _attack_cooldown.
func _update_shambler_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif _attack_anim_timer > 0.0 or _zombie_state == ZombieState.ATTACK:
		action = "attack"
	elif velocity.length_squared() > 1.0:
		action = "walk"
	else:
		action = "idle"
	var dir: String = _world_facing_to_sprite_dir(facing_dir)
	var anim_name := "%s_%s" % [action, dir]
	if String(sprite.animation) != anim_name:
		sprite.play(anim_name)
