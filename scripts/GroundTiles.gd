extends TileMapLayer

# Ground rendering. Builds a procedural tile atlas at runtime (no art assets)
# and paints the map with a designed street network rather than a uniform grid.
#
# Layout: four major roads divide the 192x192 map into a 3x3 cell grid. Roads
# are 4 tiles wide (dark asphalt), edged by 2-tile sidewalks (lighter grey).
# District cells sit between roads, filled with dirt + scattered vegetation
# so each district reads as a distinct surface from the eye of the camera.
#
# The roads + sidewalks give the eye structure to latch onto - the previous
# x%16/y%16 sidewalk stamp produced a flat plaid pattern because there was no
# road for the sidewalk to edge.

const TILE_PX := 32
const MAP_TILES := 192

# Tile atlas indices. Order matters: each appends one column to the atlas.
const STREET := 0
const SIDEWALK := 1
const RUBBLE := 2
const VEGETATION := 3
const DIRT := 4
const ASPHALT := 5

const TILE_COLORS := [
	Color("3a3a3a"),  # street - weathered cobble/asphalt mix, used as ambient road fill
	Color("5e5e5e"),  # sidewalk - light grey concrete (lighter than asphalt for contrast)
	Color("2a2520"),  # rubble - edge band, non-buildable
	Color("3a4a35"),  # vegetation - moss/weeds
	Color("4a3a30"),  # dirt - district interior fill
	Color("1c1c1c"),  # asphalt - dark road surface
]

const EDGE_MARGIN := 6

# Road centerlines (tile coordinates of the center of each 4-tile-wide road).
# Roads run the full map length and divide it into a 3x3 grid of district cells.
const ROAD_LANES_X := [65, 126]
const ROAD_LANES_Y := [65, 126]

# Distance from road centerline: 0..1 = road body (4 tiles), 2..3 = sidewalk band.
const ROAD_HALF_WIDTH := 1
const SIDEWALK_BAND := 2


func _ready() -> void:
	add_to_group("ground_tiles")
	_build_tileset()
	_populate()


func get_tile_type_at(world_pos: Vector2) -> int:
	var local_pos := to_local(world_pos)
	var cell := local_to_map(local_pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= MAP_TILES or cell.y >= MAP_TILES:
		return -1
	var atlas := get_cell_atlas_coords(cell)
	return atlas.x


func _build_tileset() -> void:
	var count: int = TILE_COLORS.size()
	var img := Image.create(TILE_PX * count, TILE_PX, false, Image.FORMAT_RGBA8)
	for i in range(count):
		var col: Color = TILE_COLORS[i]
		for px in range(TILE_PX):
			for py in range(TILE_PX):
				img.set_pixel(i * TILE_PX + px, py, col)
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
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

	# Roads take priority over sidewalks take priority over interior fill.
	if _on_road(x, y):
		return ASPHALT
	if _on_sidewalk(x, y):
		return SIDEWALK

	# District-interior ambient. Two-tier scatter so the eye sees variation
	# without it reading as noise: small chance of vegetation patches, a moderate
	# chance of weathered street tiles, otherwise dirt fill.
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
	# Two-tile sidewalk band on each side of every road. We're on sidewalk if
	# we're outside the road body but within SIDEWALK_BAND of a centerline.
	for lane_x in ROAD_LANES_X:
		var d: int = abs(x - lane_x)
		if d > ROAD_HALF_WIDTH and d <= ROAD_HALF_WIDTH + SIDEWALK_BAND:
			return true
	for lane_y in ROAD_LANES_Y:
		var d: int = abs(y - lane_y)
		if d > ROAD_HALF_WIDTH and d <= ROAD_HALF_WIDTH + SIDEWALK_BAND:
			return true
	return false
