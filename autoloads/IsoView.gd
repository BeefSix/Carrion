extends Node

# Three-quarters perspective projection helpers. Autoloaded so any node can
# convert between world coordinates (the logical / gameplay coordinate space,
# unchanged from the previous top-down view) and screen coordinates.
#
# World coordinates are still pixels in a 192x192 tile grid at TILE_WORLD_PX=32
# per tile - all gameplay math (range checks, distance, navigation, physics)
# continues to use world coords. Rendering applies world_to_screen at draw time.
#
# Projection: 2:1 dimetric iso (industry standard — Diablo II, StarCraft,
# AoE2, Tiled, Godot iso tutorials, Pixellab's iso tile output, every
# Blender iso rig). Each tile renders 64 wide x 32 tall on screen.
# Previously was 4:3 oblique (64x48, steeper tilt); migrated 2026-06-09
# per docs/PROJECTION_AUDIT.md to align with the entire iso art-tooling
# ecosystem. If "stronger tilt" is wanted aesthetically, render assets at
# a steeper Blender/Pixellab camera angle while keeping the grid 2:1
# (Project Zomboid's approach).
#
# Formula (unchanged shape, ISO_TILE_H is the only knob):
#   screen_x = (tile_x - tile_y) * ISO_TILE_W / 2
#   screen_y = (tile_x + tile_y) * ISO_TILE_H / 2 - height

const TILE_WORLD_PX = 32.0
const ISO_TILE_W = 64.0
const ISO_TILE_H = 32.0

# Godot 2D's z_index is bounded to [-4096, 4096]. World depth in this project
# can reach 12288 (corner at x+y = 6144+6144), so we scale before clamping.
# Z_DEPTH_SCALE chosen so the full world range fits comfortably inside the
# z_index window while still giving fine-grained sort resolution between
# adjacent entities.
const Z_DEPTH_SCALE = 8


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


func z_for(world_pos):
	# Convert a world position to a z_index for back-to-front rendering.
	# Use this from every renderable that participates in iso depth-sort:
	# Unit (per-frame, since they move), Building (once at _ready), Corpse, Wall.
	var d = (world_pos.x + world_pos.y) / Z_DEPTH_SCALE
	return clamp(int(d), -4000, 4000)
