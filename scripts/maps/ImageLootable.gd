extends "res://scripts/Lootable.gd"

# Image-map phantom lootable (2026-06-11): on image-first maps the
# BUILDING ART IS BAKED INTO THE BACKDROP, so this node renders nothing
# of its own — it is the building's gameplay shadow: collision, nav
# obstruction (exact footprint via nav_poly_world), loot/infestation
# state, selection, HP. The visual lives in the painting.

# Exact world-space footprint polygon (the inverse-projected image rect)
# consumed by Main._rebake_navigation instead of the axis-aligned rect.
var nav_poly_world: PackedVector2Array = PackedVector2Array()


func _get_skin_path() -> String:
	return ""  # never a skin — the backdrop is the skin


func _get_faction_dressing() -> String:
	return ""


func _draw() -> void:
	# Game-state overlays ONLY (no prism, no art): selection ring on the
	# footprint diamond, HP bar when damaged, infested marker pulse.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var hw: float = size_pixels.x * 0.5
	var hh: float = size_pixels.y * 0.5
	var nw: Vector2 = IsoView.world_to_screen(Vector2(-hw, -hh))
	var ne: Vector2 = IsoView.world_to_screen(Vector2(hw, -hh))
	var se: Vector2 = IsoView.world_to_screen(Vector2(hw, hh))
	var sw: Vector2 = IsoView.world_to_screen(Vector2(-hw, hh))
	if selected:
		draw_polyline(PackedVector2Array([nw, ne, se, sw, nw]), Color(1, 1, 0.4), 2.0, true)
	if is_infested:
		# Subtle sickly pulse ring so infested houses read as targets even
		# though the ruin art is baked. Render-only.
		draw_polyline(PackedVector2Array([nw, ne, se, sw, nw]), Color(0.5, 0.75, 0.3, 0.35), 1.5, true)
	if current_hp < max_hp:
		var bar_w: float = max(size_pixels.x * 0.7, 32.0)
		var bar_y: float = nw.y - 14.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), Color(0.12, 0.05, 0.05))
		var fill: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * fill, 3.0), Color(0.35, 0.65, 0.3))
