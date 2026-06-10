extends Node2D

# Faction ground halo (MapCraft C, 2026-06-11). RENDER-ONLY: the ground
# under a faction building carries that faction's identity — Tribal ash
# and bone, Military boot-worn mud, Survivor swept renovation. One node
# per dressed building, spawned by Building._spawn_dressing, freed with
# its owner. Sits at z 2 with the wear decals: above tiles and fringes,
# under every unit and building.

var texture: Texture2D = null
var scale_factor: float = 2.4


func _ready() -> void:
	z_index = 2
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var screen: Vector2 = IsoView.world_to_screen(position)
	var s: Vector2 = texture.get_size()
	var h: int = ((int(position.x) * 73856093) ^ (int(position.y) * 19349663)) & 0x7FFFFFFF
	var flip: float = -1.0 if ((h >> 9) & 1) == 1 else 1.0
	# Squash the top-down art onto the 2:1 iso ground plane.
	draw_set_transform(screen - position, 0.0, Vector2.ONE)
	draw_set_transform(screen, 0.0, Vector2(flip * scale_factor, 0.5 * scale_factor))
	draw_texture(texture, -s * 0.5)
