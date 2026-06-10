extends Node

# World geometry constants — the single source of truth (AUDIT.md
# constants-consolidation item, 2026-06-10). Every "6144", "192", "32.0",
# and "50.0..6094.0" hardcode traces here; never re-hardcode them
# (CLAUDE.md architecture conventions).

const TILE_PX := 32.0                 # world pixels per ground tile
const GRID_TILES := 192               # map edge length in tiles
const MAP_SIZE_PX := 6144.0           # GRID_TILES * TILE_PX
const MAP_SIZE := Vector2(6144, 6144)

# Movement/wander clamp band: keeps targets a safe margin inside the map
# edge so navigation never paths against the world boundary.
const CLAMP_MIN := 50.0
const CLAMP_MAX := 6094.0             # MAP_SIZE_PX - CLAMP_MIN


static func clamp_to_world(p: Vector2) -> Vector2:
	return Vector2(clamp(p.x, CLAMP_MIN, CLAMP_MAX), clamp(p.y, CLAMP_MIN, CLAMP_MAX))
