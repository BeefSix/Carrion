extends Node

# Three-quarters perspective projection helpers. Autoloaded so any node can
# convert between world coordinates (the logical / gameplay coordinate space,
# unchanged from the previous top-down view) and screen coordinates (the
# rendered position after iso projection).
#
# World coordinates are still pixels in a 192x192 tile grid at TILE_WORLD_PX=32
# per tile - all gameplay math (range checks, distance, navigation, physics)
# continues to use world coords. Rendering applies world_to_screen at draw time.
#
# Projection is classic 2:1 isometric:
#   screen_x = (tile_x - tile_y) * ISO_TILE_W / 2
#   screen_y = (tile_x + tile_y) * ISO_TILE_H / 2 - height

const TILE_WORLD_PX = 32.0
const ISO_TILE_W = 64.0
const ISO_TILE_H = 32.0


func world_to_screen(world_pos, height = 0.0):
	var tile_x = world_pos.x / TILE_WORLD_PX
	var tile_y = world_pos.y / TILE_WORLD_PX
	var screen_x = (tile_x - tile_y) * (ISO_TILE_W * 0.5)
	var screen_y = (tile_x + tile_y) * (ISO_TILE_H * 0.5) - height
	return Vector2(screen_x, screen_y)


func screen_to_world(screen_pos):
	var iso_dx = screen_pos.x / (ISO_TILE_W * 0.5)
	var iso_dy = screen_pos.y / (ISO_TILE_H * 0.5)
	var tile_x = (iso_dx + iso_dy) * 0.5
	var tile_y = (iso_dy - iso_dx) * 0.5
	return Vector2(tile_x * TILE_WORLD_PX, tile_y * TILE_WORLD_PX)


func depth_for(world_pos):
	return world_pos.x + world_pos.y
