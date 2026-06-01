class_name Projectile
extends Area2D

# Direct-fire projectile. Travels in a straight line from origin to a velocity
# direction; on first collision with a CollisionObject2D (Unit or Building/Wall
# StaticBody2D) resolves damage if applicable and despawns. Arc variant
# (parabolic / AOE) deferred until a unit needs it.
#
# World-space gameplay coords; iso-projected in _draw to match Unit/Corpse.

enum Type { DIRECT, ARCING }

# Friendly fire applies damage to anyone the projectile hits regardless of
# faction. The doc explicitly opts in. Flip to false if balance breaks.
const FRIENDLY_FIRE_ENABLED := true
# Safety despawn. A projectile that misses everything despawns rather than
# flying forever and leaking memory.
const DEFAULT_LIFETIME := 5.0

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

var _time_alive: float = 0.0
var _resolved: bool = false


func _ready() -> void:
	add_to_group("projectiles")
	body_entered.connect(_on_body_entered)


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
	position = origin
	var dir: Vector2 = target_pos - origin
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	velocity = dir.normalized() * speed
	rotation = dir.angle()


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_time_alive += delta
	if _time_alive >= DEFAULT_LIFETIME:
		_despawn()
		return
	position += velocity * delta
	z_index = IsoView.z_for(position)
	queue_redraw()


func _on_body_entered(body) -> void:
	if _resolved:
		return
	# Ignore the firer for the first frame to avoid spawn-collision when the
	# projectile spawns inside the firer's collision shape.
	if body == firer:
		return
	if body.is_in_group("units"):
		_resolve_impact_on_unit(body)
		return
	# Walls + buildings absorb without taking damage. Both are StaticBody2D
	# tagged "buildings" or "walls". Anything else solid: despawn safely.
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
	# Unit/Corpse/Building.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	# Phase 1: simple tracer line trailing behind the projectile head.
	var dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0 else Vector2.RIGHT
	var tail: Vector2 = -dir * visual_length
	draw_line(tail, Vector2.ZERO, visual_color, visual_width)
