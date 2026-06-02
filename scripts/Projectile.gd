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
#   TRACER - Military: bright thin line trailing the head (rifle/HG bullets)
#   ARROW  - Tribal: triangular head + thin shaft + fletching polygon
#   BOLT   - Survivor: dark elongated rectangle (crossbow bolt). Reserved -
#            no Survivor combat unit currently fires projectiles.
enum Style { TRACER, ARROW, BOLT }

# Friendly fire applies damage to anyone the projectile hits regardless of
# faction. The doc explicitly opts in. Flip to false if balance breaks.
const FRIENDLY_FIRE_ENABLED := true
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

var _time_alive: float = 0.0
var _resolved: bool = false


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
	rotation = dir.angle()


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
	var query := PhysicsRayQueryParameters2D.create(position, new_pos, MOTION_MASK)
	# Exclude the firer's RID so the projectile doesn't immediately collide with
	# its own shooter on spawn. is_instance_valid guards against firer being
	# freed mid-flight (the projectile keeps flying).
	if firer != null and is_instance_valid(firer):
		query.exclude = [firer.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		position = hit.get("position", new_pos)
		z_index = IsoView.z_for(position)
		queue_redraw()
		_resolve_collision(hit.get("collider", null))
		return
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
	if collider.is_in_group("buildings"):
		if collider.has_method("take_damage"):
			var reduced: int = max(1, int(round(damage * BUILDING_DAMAGE_FRACTION)))
			collider.take_damage(reduced)
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
	var r_sq: float = area_radius * area_radius
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if not FRIENDLY_FIRE_ENABLED and u.faction == faction:
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
	# Iso shift: render at iso-projected screen position. Same pattern as
	# Unit/Corpse/Building. All coordinates below are local to the projectile;
	# the iso transform places the local origin at the iso screen position.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	# Visual direction is the iso-projected velocity, not the world velocity.
	# Iso projection skews motion: world-east maps to screen-(east + south).
	var dir: Vector2 = _iso_direction(velocity)
	# Clamp the visible length to actual iso-screen distance traveled from the
	# origin so the tail never extends behind the firer. Otherwise, at spawn
	# the tracer's tail point is visual_length px behind the head - which is
	# behind/off-screen-of the firing unit until the projectile has moved a
	# tracer-length forward. Reads as "tracer flying from behind the unit."
	var origin_iso: Vector2 = IsoView.world_to_screen(origin)
	var pos_iso: Vector2 = IsoView.world_to_screen(position)
	var iso_travel: float = origin_iso.distance_to(pos_iso)
	var effective_length: float = min(visual_length, iso_travel)
	match visual_style:
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
