extends Node2D

# Map prop / doodad (2026-06-10). RENDER-ONLY world dressing — the SC1
# doodad, minus the footprint: no collision, no groups the sim reads, no
# nav impact. Placement comes from MapRecipes' deterministic scatter, so
# every client draws the same clutter, but nothing here can touch the
# sim. If a prop class ever needs collision (cars as cover?), that's a
# gameplay change — route it through a StaticBody scene + nav rebake and
# a design ruling, not this script.

@export var texture: Texture2D = null


func _ready() -> void:
	z_index = IsoView.z_for(position)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	# Same iso projection pattern as Unit/Building _draw: position is sim/
	# world space; the offset moves the visual to screen space.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var s: Vector2 = texture.get_size()
	# Drop shadow (MapCraft A): same SE light source as buildings — a
	# squashed dark ellipse under the base grounds the prop.
	draw_set_transform(iso_offset + Vector2(s.x * 0.10, 0.0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 2), s.x * 0.38, Color(0.04, 0.04, 0.05, 0.38))
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	# Bottom-anchored: the sprite's base sits on the ground at position.
	# Mirror by position hash (MapCraft A): identical wrecks all facing one
	# way is the prop equivalent of the repeated-building tell.
	var h: int = ((int(position.x) * 2654435761) ^ (int(position.y) * 40503)) & 0x7FFFFFFF
	if ((h >> 9) & 1) == 1:  # high bit: positions are lattice-aligned
		draw_set_transform(iso_offset, 0.0, Vector2(-1.0, 1.0))
	draw_texture(texture, Vector2(-s.x * 0.5, -s.y + 4.0))
