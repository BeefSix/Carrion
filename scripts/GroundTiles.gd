extends TileMapLayer

# Ground rendering. Builds a procedural diamond-tile atlas at runtime and uses
# Godot's TILE_SHAPE_ISOMETRIC to lay tiles out at three-quarters perspective.
#
# World coordinates still drive gameplay (positions in pixels, 32 px = 1 tile).
# The tile_set is configured for iso 2:1 - each tile is a 64x32 diamond on
# screen, the same projection Projection.world_to_screen produces.
#
# Layout: four major roads divide the 192x192 grid into a 3x3 cell pattern.
# Roads are 4 tiles wide (dark asphalt), edged by 2-tile sidewalk bands.
# District cells sit between roads.

const TILE_W := 64
const TILE_H := 48  # 4:3 tile aspect (was 32 for 2:1 - matches IsoView.ISO_TILE_H)
const MAP_TILES := 192

const STREET := 0
const SIDEWALK := 1
const RUBBLE := 2
const VEGETATION := 3
const DIRT := 4
const ASPHALT := 5

const TILE_COLORS := [
	Color("3a3a3a"),  # street - weathered asphalt ambient
	Color("5e5e5e"),  # sidewalk - light grey concrete
	Color("2a2520"),  # rubble - edge band
	Color("3a4a35"),  # vegetation - moss/weeds
	Color("4a3a30"),  # dirt - district interior fill
	Color("1c1c1c"),  # asphalt - dark road surface
]

const EDGE_MARGIN := 6

const ROAD_LANES_X := [65, 126]
const ROAD_LANES_Y := [65, 126]
const ROAD_HALF_WIDTH := 1
const SIDEWALK_BAND := 2


func _ready() -> void:
	add_to_group("ground_tiles")
	_build_tileset()
	_populate()


func get_tile_type_at(world_pos: Vector2) -> int:
	# Convert world (pixel) position to tile cell via Projection so callers can
	# still query "what's under this world location" without thinking in iso.
	var tile_x: int = int(world_pos.x / IsoView.TILE_WORLD_PX)
	var tile_y: int = int(world_pos.y / IsoView.TILE_WORLD_PX)
	if tile_x < 0 or tile_y < 0 or tile_x >= MAP_TILES or tile_y >= MAP_TILES:
		return -1
	var atlas := get_cell_atlas_coords(Vector2i(tile_x, tile_y))
	return atlas.x


func _build_tileset() -> void:
	# Each tile texture is TILE_W x TILE_H (64x32) with a diamond-masked color.
	# Pixels inside the diamond get the tile color; pixels outside are fully
	# transparent so adjacent diamonds tile cleanly without overlap.
	var count: int = TILE_COLORS.size()
	var img := Image.create(TILE_W * count, TILE_H, false, Image.FORMAT_RGBA8)
	var cx: float = TILE_W * 0.5
	var cy: float = TILE_H * 0.5
	for i in range(count):
		var col: Color = TILE_COLORS[i]
		var x_offset: int = i * TILE_W
		for px in range(TILE_W):
			for py in range(TILE_H):
				# 2:1 diamond: |dx|/half_w + |dy|/half_h <= 1
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


func _populate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			set_cell(Vector2i(x, y), 0, Vector2i(_tile_type_at(x, y, rng), 0))


func _tile_type_at(x: int, y: int, rng: RandomNumberGenerator) -> int:
	if _is_edge(x, y):
		return RUBBLE if (x + y) % 5 == 0 else DIRT
	if _on_road(x, y):
		return ASPHALT
	if _on_sidewalk(x, y):
		return SIDEWALK
	var roll: float = rng.randf()
	if roll < 0.04:
		return VEGETATION
	if roll < 0.16:
		return STREET
	return DIRT


func _is_edge(x: int, y: int) -> bool:
	return x < EDGE_MARGIN or y < EDGE_MARGIN or x >= MAP_TILES - EDGE_MARGIN or y >= MAP_TILES - EDGE_MARGIN


func _on_road(x: int, y: int) -> bool:
	for lane_x in ROAD_LANES_X:
		if abs(x - lane_x) <= ROAD_HALF_WIDTH:
			return true
	for lane_y in ROAD_LANES_Y:
		if abs(y - lane_y) <= ROAD_HALF_WIDTH:
			return true
	return false


func _on_sidewalk(x: int, y: int) -> bool:
	for lane_x in ROAD_LANES_X:
		var d: int = abs(x - lane_x)
		if d > ROAD_HALF_WIDTH and d <= ROAD_HALF_WIDTH + SIDEWALK_BAND:
			return true
	for lane_y in ROAD_LANES_Y:
		var d: int = abs(y - lane_y)
		if d > ROAD_HALF_WIDTH and d <= ROAD_HALF_WIDTH + SIDEWALK_BAND:
			return true
	return false
