extends Node

# Factory + registry for active projectiles. Combat units call
# spawn_projectile(config) instead of applying damage directly; the projectile
# travels in world space and resolves damage on impact.
#
# Config dict keys (Phase 1 - DIRECT only):
#   origin: Vector2          - spawn position (typically firer.global_position)
#   target_pos: Vector2      - aimed position (target's current global_position)
#   damage: float            - damage applied on hit
#   speed: float             - projectile speed in px/sec
#   firer: Unit              - kill credit + spawn-collision suppression
#   target: Unit             - intended target (informational, not enforced)
#   faction: int             - Unit.Faction value for friendly-fire check
#   type: Projectile.Type    - DIRECT (default) or ARCING (Phase 2+)
#   area_radius: float       - ARCING only
#   color, visual_length,
#   visual_width             - per-faction visual differentiation

# Signal payloads stay untyped here because the Projectile class_name is
# resolved at runtime via the scene preload; declaring the parameter type at
# parse time fails autoload registration.
signal projectile_spawned(projectile)
signal projectile_impacted(projectile, target)

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

var _active_projectiles: Array = []


func spawn_projectile(config: Dictionary):
	var proj = PROJECTILE_SCENE.instantiate()
	proj.configure(config)
	# Parent under the firer's parent (Main) so world coords stay consistent.
	# If firer is gone (edge case), fall back to current scene root.
	var parent: Node = null
	var firer = config.get("firer", null)
	if firer != null and is_instance_valid(firer) and firer.get_parent() != null:
		parent = firer.get_parent()
	else:
		parent = get_tree().current_scene
	if parent == null:
		proj.queue_free()
		return null
	parent.add_child(proj)
	_active_projectiles.append(proj)
	# Auto-remove from registry on despawn. Without this the array grew
	# monotonically across a match - every spawn appended, no erase - and
	# any pass that scanned the registry got progressively slower.
	proj.tree_exited.connect(_on_projectile_exited.bind(proj))
	projectile_spawned.emit(proj)
	return proj


func _on_projectile_exited(proj) -> void:
	_active_projectiles.erase(proj)


func cleanup_all() -> void:
	# Match-restart cleanup. Free any in-flight projectiles before the next
	# match begins so stale references don't survive a title-screen round trip.
	for p in _active_projectiles:
		if is_instance_valid(p):
			p.queue_free()
	_active_projectiles.clear()


func get_active_count() -> int:
	# Prune dead refs lazily so callers see an accurate live count.
	var live: Array = []
	for p in _active_projectiles:
		if is_instance_valid(p):
			live.append(p)
	_active_projectiles = live
	return _active_projectiles.size()
