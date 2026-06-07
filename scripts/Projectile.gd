class_name Projectile
extends Area2D

# Direct-fire projectile. Travels in a straight line from origin to a velocity
# direction; on first collision with a CollisionObject2D (Unit or Building/Wall
# StaticBody2D) resolves damage if applicable and despawns. Arc variant
# (parabolic / AOE) deferred until a unit needs it.
#
# World-space gameplay coords; iso-projected in _draw to match Unit/Corpse.

enum Type { DIRECT, ARCING }
# Visual style controls how _draw renders the projectile in flight. Matches
# each faction's projectile identity.
#   BULLET - Military: small bright dot. Reads as an individual bullet, not
#            a tracer streak. Use with slower projectile speeds.
#   TRACER - Legacy long-line tracer. Replaced by BULLET for Military but
#            kept in the enum for future fast-projectile mechanics.
#   ARROW  - Tribal: triangular head + thin shaft + fletching polygon.
#            Elongated geometry is what makes an arrow read as an arrow.
#   BOLT   - Survivor: dark elongated rectangle (crossbow bolt). Reserved.
enum Style { TRACER, ARROW, BOLT, BULLET }

# Friendly fire pass-through: same-faction units don't take projectile damage
# when this is false. Per user feedback - the design tension between "bullets
# are physical" and "your own troops cluster in formation" lands on the latter.
const FRIENDLY_FIRE_ENABLED := false
# Safety despawn. A projectile that misses everything despawns rather than
# flying forever and leaking memory.
const DEFAULT_LIFETIME := 5.0
# Bullets chip walls and buildings at reduced effectiveness. AOE / explosives
# remain the efficient siege options per the audit response #3.
const BUILDING_DAMAGE_FRACTION := 0.15
# Collision mask for the per-frame motion raycast. Bit 0 = units (CharacterBody2D),
# bit 1 = walls/buildings (StaticBody2D on layer 2). Matches scene mask.
const MOTION_MASK := 3

var damage: float = 10.0
var speed: float = 800.0
var projectile_type: int = Type.DIRECT
var area_radius: float = 0.0  # used by ARCING type (Phase 2+)

var origin: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var firer = null  # Unit who fired - kill credit + spawn-collision suppression
var intended_target = null  # tracked but not enforced; projectile hits first solid
var faction: int = 0  # Unit.Faction; used for friendly-fire decision
var visual_color: Color = Color(0.95, 0.7, 0.3)
var visual_length: float = 14.0
var visual_width: float = 2.0
var visual_style: int = Style.TRACER
# Render height above the iso ground (in screen pixels). Default ~10 px puts
# the projectile at chest/gun height of a standard size_px=22 unit silhouette
# rather than at the unit's feet. The Unit silhouette extends roughly y=-1
# (feet) to y=-16 (head) in iso-screen space; chest is around y=-10.
var visual_height: float = 10.0

var _time_alive: float = 0.0
var _resolved: bool = false

# Smoke trail: recent world positions stored for fading-puff render behind
# the bullet. Capped at TRAIL_MAX entries; older entries drop off.
const TRAIL_MAX := 6
var _trail_points: Array = []


func _ready() -> void:
	add_to_group("projectiles")
	# Collision detection is done per-frame via raycast in _physics_process to
	# avoid tunneling at high speeds. body_entered is unreliable for fast
	# projectiles because the area can leap past a target between frames.


func configure(config: Dictionary) -> void:
	# Called by ProjectileManager.spawn_projectile right after instantiation,
	# before adding to the tree. All fields read from the config dict.
	origin = config.get("origin", Vector2.ZERO)
	target_pos = config.get("target_pos", Vector2.ZERO)
	damage = config.get("damage", 10.0)
	speed = config.get("speed", 800.0)
	firer = config.get("firer", null)
	intended_target = config.get("target", null)
	projectile_type = config.get("type", Type.DIRECT)
	area_radius = config.get("area_radius", 0.0)
	faction = config.get("faction", 0)
	visual_color = config.get("color", visual_color)
	visual_length = config.get("visual_length", visual_length)
	visual_width = config.get("visual_width", visual_width)
	visual_style = config.get("style", Style.TRACER)
	visual_height = config.get("visual_height", visual_height)
	position = origin
	var dir: Vector2 = target_pos - origin
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	# Accuracy spread: rotate the aim vector by a random angle within
	# +/- spread_deg. Effective spread is computed by the firer (base
	# accuracy minus the leadership-aura accuracy bonus).
	var spread_deg: float = config.get("spread_deg", 0.0)
	if spread_deg > 0.0:
		var offset_deg: float = randf_range(-spread_deg, spread_deg)
		dir = dir.rotated(deg_to_rad(offset_deg))
	velocity = dir * speed
	# IMPORTANT: do NOT set node rotation. The draw helpers use _iso_direction
	# to orient their own geometry; setting rotation here rotates the
	# draw_set_transform iso_offset around the node origin, sending the bullet
	# to a position-and-velocity-dependent wrong spot on screen.
	rotation = 0.0
	# Set z_index from frame 0 (otherwise the default 0 lets ground/buildings
	# render over the bullet for one frame before _physics_process catches up).
	z_index = IsoView.z_for(position)


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_time_alive += delta
	if _time_alive >= DEFAULT_LIFETIME:
		_despawn()
		return
	# Per-frame raycast from current to next position. At 1600 px/s and 60Hz
	# physics, projectiles travel ~27 px per frame - larger than typical unit
	# collision shapes (~22 px). Area2D body_entered relies on overlap at
	# physics-frame snapshots, so fast projectiles silently tunnel past targets.
	# Raycasting catches everything in the swept path.
	var new_pos: Vector2 = position + velocity * delta
	var space := get_world_2d().direct_space_state
	# Raycast with firer-only exclude. If a friendly is in the path, hop past
	# them and retry. Replaces the previous "exclude every same-faction unit
	# upfront" pattern which iterated all units in the scene every frame for
	# every projectile - the primary cause of the late-match perf degradation.
	# Now O(friendlies-in-path) per frame instead of O(all-friendlies).
	var excludes_arr: Array[RID] = []
	if firer != null and is_instance_valid(firer):
		excludes_arr.append(firer.get_rid())
	var current_start: Vector2 = position
	var hops: int = 0
	while hops < 8:  # safety cap, friendly chain in the line of fire is rarely > 2
		var query := PhysicsRayQueryParameters2D.create(current_start, new_pos, MOTION_MASK)
		query.exclude = excludes_arr
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider = hit.get("collider", null)
		if (not FRIENDLY_FIRE_ENABLED) and collider != null \
				and collider.is_in_group("units") \
				and "faction" in collider \
				and collider.faction == faction:
			var hit_pos: Vector2 = hit.get("position", current_start)
			current_start = hit_pos + velocity.normalized() * 2.0
			excludes_arr.append(collider.get_rid())
			hops += 1
			continue
		# Real hit - resolve and despawn.
		position = hit.get("position", new_pos)
		z_index = IsoView.z_for(position)
		_trail_points.append(position)
		if _trail_points.size() > TRAIL_MAX:
			_trail_points.pop_front()
		queue_redraw()
		_resolve_collision(collider)
		return
	# No real hit this frame.
	_trail_points.append(position)
	if _trail_points.size() > TRAIL_MAX:
		_trail_points.pop_front()
	position = new_pos
	z_index = IsoView.z_for(position)
	queue_redraw()


func _resolve_collision(collider) -> void:
	if collider == null:
		_despawn()
		return
	if collider.is_in_group("units"):
		_resolve_impact_on_unit(collider)
		return
	# Buildings (walls included) take reduced damage from bullets. AOE/explosives
	# remain the efficient siege option; bullets chip slowly.
	# Friendly fire on own walls: a Rifleman should not be chipping his own
	# wall when firing through it. Routed through GameState.is_hostile so the
	# rule matches the unit-vs-unit friendly-fire policy (FRIENDLY_FIRE_ENABLED).
	if collider.is_in_group("buildings"):
		if not FRIENDLY_FIRE_ENABLED \
				and firer != null and is_instance_valid(firer) \
				and not GameState.is_hostile(firer, collider):
			_despawn()
			return
		if collider.has_method("take_damage"):
			var reduced: int = max(1, int(round(damage * BUILDING_DAMAGE_FRACTION)))
			collider.take_damage(reduced, firer)
	_despawn()


func _resolve_impact_on_unit(target_unit) -> void:
	if not FRIENDLY_FIRE_ENABLED and target_unit.faction == faction:
		# Same-faction hit, friendly fire off -> pass through. Despawn to avoid
		# the projectile re-triggering on adjacent allies in formation.
		_despawn()
		return
	if area_radius > 0.0:
		_apply_area_damage(position)
	elif target_unit.has_method("take_damage"):
		target_unit.take_damage(int(round(damage)), firer)
	_despawn()


func _apply_area_damage(center: Vector2) -> void:
	# Used by area-on-impact direct shots (e.g. HG) and by arcing projectiles
	# on landing (Phase 2+). Damages units in radius, and HQs of the opposing
	# side for the win-condition splash that HG previously had.
	# H4 follow-up: friendly-fire skip routed through GameState.is_hostile so
	# the Military mirror's HG splash actually damages opposing-team Military
	# (faction equality would have skipped them like the targeting bug).
	var r_sq: float = area_radius * area_radius
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if not FRIENDLY_FIRE_ENABLED:
			var is_friendly: bool
			if firer != null and is_instance_valid(firer):
				is_friendly = not GameState.is_hostile(firer, u)
			else:
				# Firer died mid-flight - degenerate case, fall back to
				# faction equality so the splash still avoids own-faction
				# units (the projectile retains its faction value).
				is_friendly = u.faction == faction
			if is_friendly:
				continue
		if u.global_position.distance_squared_to(center) <= r_sq:
			if u.has_method("take_damage"):
				u.take_damage(int(round(damage)), firer)
	# Opposing HQ splash (preserves HG's anti-HQ AOE from before projectiles).
	# Group selection mirrors the unit's own ownership tag.
	var enemy_group: String = ""
	if firer != null and is_instance_valid(firer):
		enemy_group = "player_buildings" if firer.is_in_group("ai_units") else "ai_buildings"
	if enemy_group != "":
		for b in get_tree().get_nodes_in_group(enemy_group):
			if not is_instance_valid(b) or not b.is_in_group("hq"):
				continue
			if b.global_position.distance_squared_to(center) <= r_sq:
				if b.has_method("take_damage"):
					b.take_damage(int(round(damage)))


func _despawn() -> void:
	if _resolved:
		return
	_resolved = true
	queue_free()


func _draw() -> void:
	# Iso shift: render at iso-projected screen position, raised by
	# visual_height so the bullet appears at the firer's chest/gun height
	# rather than at their feet (the unit silhouette extends UP from the
	# iso-projected world position, so the world position is at the feet).
	var iso_offset: Vector2 = IsoView.world_to_screen(position, visual_height) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	# Visual direction is the iso-projected velocity, not the world velocity.
	# Iso projection skews motion: world-east maps to screen-(east + south).
	var dir: Vector2 = _iso_direction(velocity)
	# Clamp the visible length to actual iso-screen distance traveled from the
	# origin so the tail never extends behind the firer. Otherwise, at spawn
	# the tracer's tail point is visual_length px behind the head - which is
	# behind/off-screen-of the firing unit until the projectile has moved a
	# tracer-length forward. Reads as "tracer flying from behind the unit."
	var origin_iso: Vector2 = IsoView.world_to_screen(origin, visual_height)
	var pos_iso: Vector2 = IsoView.world_to_screen(position, visual_height)
	var iso_travel: float = origin_iso.distance_to(pos_iso)
	var effective_length: float = min(visual_length, iso_travel)
	match visual_style:
		Style.BULLET:
			_draw_bullet()
		Style.TRACER:
			_draw_tracer(dir, effective_length)
		Style.ARROW:
			_draw_arrow(dir, effective_length)
		Style.BOLT:
			_draw_bolt(dir, effective_length)


func _iso_direction(world_velocity: Vector2) -> Vector2:
	# Project world velocity through the iso transform (linear part) to get
	# the screen-space direction of motion. Matches IsoView.world_to_screen's
	# coefficients: screen_x = world_x - world_y, screen_y = 0.75*(world_x + world_y).
	var sv := Vector2(
		world_velocity.x - world_velocity.y,
		(world_velocity.x + world_velocity.y) * 0.75,
	)
	if sv.length_squared() < 0.01:
		return Vector2.RIGHT
	return sv.normalized()


func _draw_bullet() -> void:
	# Elongated bullet-shaped polygon with smoke trail puffs trailing behind.
	# visual_width is the bullet's half-width; length is derived as a multiple
	# of that. All coordinates here are in canvas-item space; the iso transform
	# was applied at the top of _draw().
	var r: float = max(visual_width, 2.0)
	var dir: Vector2 = _iso_direction(velocity)

	# Smoke trail first (renders behind the bullet). Each past world position
	# is iso-projected and drawn as a fading gray puff. Older points are more
	# faded and slightly smaller; newer points are nearly as bright as smoke.
	var current_iso: Vector2 = IsoView.world_to_screen(position, visual_height)
	var trail_count: int = _trail_points.size()
	for i in range(trail_count):
		var p_iso: Vector2 = IsoView.world_to_screen(_trail_points[i], visual_height)
		var local_offset: Vector2 = p_iso - current_iso
		# i = 0 is OLDEST entry; trail_count - 1 is newest. Map oldest -> small/faint,
		# newest -> larger/visible.
		var t: float = float(i + 1) / float(trail_count + 1)  # 0..1
		var alpha: float = t * 0.40
		var puff_r: float = r * (0.5 + t * 0.5)
		draw_circle(local_offset, puff_r, Color(0.75, 0.75, 0.75, alpha))

	# Bullet shape: pointed nose + curved body + rounded tail. Octagonal
	# approximation of a bullet silhouette oriented along iso direction.
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var length: float = r * 2.8
	var hw: float = r * 0.85
	var body_pts := PackedVector2Array([
		dir * (length * 0.5),                            # tip
		dir * (length * 0.25) - perp * hw * 0.55,        # nose right shoulder
		-perp * hw,                                       # mid right
		-dir * (length * 0.35) - perp * hw * 0.7,        # back right
		-dir * (length * 0.5),                            # tail
		-dir * (length * 0.35) + perp * hw * 0.7,        # back left
		perp * hw,                                        # mid left
		dir * (length * 0.25) + perp * hw * 0.55,        # nose left shoulder
	])
	# Dark outline slightly larger than body.
	var outline_pts := PackedVector2Array()
	for p in body_pts:
		outline_pts.append(p * 1.25)
	draw_colored_polygon(outline_pts, Color(0, 0, 0, 0.55))
	draw_colored_polygon(body_pts, visual_color)


func _draw_tracer(dir: Vector2, length: float) -> void:
	# Bright trailing line + a meaningfully-sized head so the eye can track
	# the projectile across frames at 1500+ px/s flight speeds. length is
	# clamped by the caller to actual travel-from-origin so the tail never
	# extends behind the firer at spawn.
	var tail: Vector2 = -dir * length
	if length > 0.5:
		draw_line(tail, Vector2.ZERO, visual_color, visual_width)
	draw_circle(Vector2.ZERO, max(visual_width * 1.2, 2.0), visual_color.lightened(0.35))


func _draw_arrow(dir: Vector2, length: float) -> void:
	# Triangular head + thin shaft + small fletching. length is clamped by the
	# caller to actual travel-from-origin so the tail never extends behind
	# the firer at spawn. When length < head_len, only the head draws.
	if length <= 0.5:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_len: float = max(visual_length * 0.30, 4.0)
	var head_half_w: float = max(visual_width, 2.0)
	# Head: triangle from base back-corners to point at origin (always drawn).
	var head_base_offset: float = min(head_len, length)
	var head_base: Vector2 = -dir * head_base_offset
	var head_pts := PackedVector2Array([
		Vector2.ZERO,
		head_base + perp * head_half_w,
		head_base - perp * head_half_w,
	])
	draw_colored_polygon(head_pts, visual_color)
	# Shaft + fletching only render once travel >= head_len so the arrow
	# doesn't visibly stretch backward in the first frames.
	if length <= head_len + 1.0:
		return
	var shaft_back: Vector2 = -dir * length
	draw_line(shaft_back, head_base, visual_color, max(visual_width * 0.6, 1.0))
	var fletch_inset: Vector2 = -dir * (length * 0.85)
	var fletch_half: float = max(visual_width * 1.3, 2.5)
	var fletch_pts := PackedVector2Array([
		shaft_back,
		fletch_inset + perp * fletch_half,
		fletch_inset - perp * fletch_half,
	])
	draw_colored_polygon(fletch_pts, visual_color.darkened(0.25))


func _draw_bolt(dir: Vector2, length: float) -> void:
	# Dark elongated rectangle. Reserved for future Survivor crossbow.
	# length clamped by caller for spawn-frame tail-behind-firer prevention.
	if length <= 0.5:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var half_w: float = max(visual_width * 0.6, 1.0)
	var tail: Vector2 = -dir * length
	var pts := PackedVector2Array([
		Vector2.ZERO + perp * half_w,
		Vector2.ZERO - perp * half_w,
		tail - perp * half_w,
		tail + perp * half_w,
	])
	draw_colored_polygon(pts, visual_color)
