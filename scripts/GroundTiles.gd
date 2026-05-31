extends TileMapLayer

# Ground rendering. Consumes a 192x192 tile_grid (PackedByteArray) produced
# by TownPlanner instead of generating tiles inline. The atlas + diamond
# textures + iso shape stay here; the spatial design moves into TownPlanner.
#
# Usage from Main:
#   var planner := TownPlanner.new()
#   var data := planner.plan_town()
#   $GroundTiles.apply_tile_grid(data["tile_grid"])

const TILE_W := 64
const TILE_H := 48
const MAP_TILES := 192

# Tile palette - indices must match TownPlanner's TILE_* constants.
const TILE_COLORS := [
	Color("2a2a2a"),  # 0 main road - very dark gray (unchanged)
	Color("5a5a5a"),  # 1 sidewalk - medium gray (unchanged)
	Color("3a3a3a"),  # 2 secondary road - dark gray (unchanged)
	Color("2f2820"),  # 3 side street - dark gray-brown (unchanged)
	Color("404040"),  # 4 parking lot - gray (unchanged)
	Color("444a36"),  # 5 yard - was #455040; muted toward dormant grass
	                  #   end-of-winter / abandoned lawn family. Lower
	                  #   saturation so units sit on top of it instead
	                  #   of being eaten by it.
	Color("46413a"),  # 6 bare ground - was #4a4035; gentler brown, less
	                  #   aggressive against neighboring green. Industrial
	                  #   zones sit closer to the residential palette family.
	Color("45382e"),  # 7 dirt road - was #4a3a30; same softer-brown
	                  #   treatment so dirt-road and bare-ground feel
	                  #   like neighbors not warring colors.
	Color("3c4032"),  # 8 vegetation - was #3a4a35; pulled toward gray,
	                  #   reads as long-abandoned overgrowth rather than
	                  #   lush wilderness.
	Color("2a2520"),  # 9 rubble - dark warm gray-brown (unchanged)
	Color("3c402e"),  # 10 fence - was #3a4632; aligned with the new yard
	                  #   family so the property-line read stays subtle.
]


func _ready() -> void:
	add_to_group("ground_tiles")
	_build_tileset()
	# Population happens via apply_tile_grid() from Main. Until then the
	# TileMapLayer is empty.


func get_tile_type_at(world_pos: Vector2) -> int:
	# Convert world (pixel) position to tile cell.
	var tile_x: int = int(world_pos.x / IsoView.TILE_WORLD_PX)
	var tile_y: int = int(world_pos.y / IsoView.TILE_WORLD_PX)
	if tile_x < 0 or tile_y < 0 or tile_x >= MAP_TILES or tile_y >= MAP_TILES:
		return -1
	var atlas := get_cell_atlas_coords(Vector2i(tile_x, tile_y))
	return atlas.x


func apply_tile_grid(grid: PackedByteArray) -> void:
	# Paint the entire 192x192 tile map from a TownPlanner-provided grid.
	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			var t: int = grid[x + y * MAP_TILES]
			set_cell(Vector2i(x, y), 0, Vector2i(t, 0))


func _build_tileset() -> void:
	# Diamond-masked atlas. TILE_W x TILE_H per tile, transparent outside the
	# diamond so adjacent iso tiles tile cleanly without overlap.
	var count: int = TILE_COLORS.size()
	var img := Image.create(TILE_W * count, TILE_H, false, Image.FORMAT_RGBA8)
	var cx: float = TILE_W * 0.5
	var cy: float = TILE_H * 0.5
	for i in range(count):
		var col: Color = TILE_COLORS[i]
		var x_offset: int = i * TILE_W
		for px in range(TILE_W):
			for py in range(TILE_H):
				var dx: float = abs(float(px) + 0.5 - cx) / cx
				var dy: float = abs(float(py) + 0.5 - cy) / cy
				if dx + dy <= 1.0:
					img.set_pixel(x_offset + px, py, col)
				else:
					img.set_pixel(x_offset + px, py, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(TILE_W, TILE_H)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_W, TILE_H)
	for i in range(count):
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	tile_set = ts
