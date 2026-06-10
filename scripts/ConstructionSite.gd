extends "res://scripts/Building.gd"

# Construction site — the SC-style scaffold (worker-built construction,
# 2026-06-10). Spawned at placement time so it blocks navigation and can
# be ATTACKED (killing a half-built Barracks is real counterplay; sunk
# cost is lost — no refund, the SC rule). A worker channels here; when
# progress completes, the real building scene replaces the site.
#
# Extends Building for free: HP plumbing, groups, iso draw transform,
# damage routing (incl. the A2 owner_controller hook if the AI ever uses
# worker construction).

const SITE_HP_FRACTION := 0.25  # scaffolds are fragile

var build_key: String = ""
var build_scene_path: String = ""
var build_time: float = 10.0
var _progress: float = 0.0
var _completed: bool = false


func setup(key: String, entry: Dictionary) -> void:
	# Called by the placement flow BEFORE add_child.
	build_key = key
	build_scene_path = entry["scene"]
	build_time = float(entry["build_time"])
	size_pixels = entry["footprint"]
	max_hp = 100  # overwritten below from the target scene's HP in _ready? keep simple flat scaffold HP
	body_color = Color(0.45, 0.42, 0.36)


func _ready() -> void:
	# Scaffold HP: flat fraction of a nominal 1000 (Building default) —
	# fragile by design. current_hp set by super from max_hp.
	max_hp = int(1000 * SITE_HP_FRACTION)
	super._ready()
	add_to_group("construction_sites")
	# Footprint blocks nav like a finished building.
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")


# Worker channel calls this every physics tick while building. Returns
# true when construction completed (worker stops channeling).
func advance_construction(delta: float) -> bool:
	if _completed:
		return true
	_progress += delta
	queue_redraw()
	if _progress < build_time:
		return false
	_completed = true
	_spawn_finished_building()
	return true


func _spawn_finished_building() -> void:
	var scene: PackedScene = load(build_scene_path)
	if scene == null:
		queue_free()
		return
	var b = scene.instantiate()
	b.position = position
	get_parent().add_child(b)
	# Ownership follows the site's groups (placement tagged us).
	for g in ["player_buildings", "ai_buildings"]:
		if is_in_group(g):
			b.add_to_group(g)
	if "owner_controller" in b and owner_controller != null:
		b.owner_controller = owner_controller
	var main = get_tree().current_scene
	if main != null and main.has_method("rebake_navigation"):
		main.call_deferred("rebake_navigation")
	queue_free()


func get_status_text() -> String:
	return "Constructing %s... %d%%" % [build_key.capitalize(), int(_progress / build_time * 100.0)]


func _draw_building_icon() -> void:
	# Scaffold cross-braces + a progress bar — reads as "under construction"
	# at a glance and shows the enemy what you're committing to (SC rule:
	# construction is public information).
	var s: Vector2 = size_pixels * 0.4
	draw_line(Vector2(-s.x, -s.y), Vector2(s.x, s.y), PALETTE_ICON_NEUTRAL, 1.5, true)
	draw_line(Vector2(-s.x, s.y), Vector2(s.x, -s.y), PALETTE_ICON_NEUTRAL, 1.5, true)
	var bar_w: float = size_pixels.x * 0.7
	var frac: float = clamp(_progress / build_time, 0.0, 1.0)
	draw_rect(Rect2(-bar_w * 0.5, s.y + 6.0, bar_w, 3.0), Color(0.15, 0.12, 0.1))
	draw_rect(Rect2(-bar_w * 0.5, s.y + 6.0, bar_w * frac, 3.0), Color(0.75, 0.65, 0.3))
