extends TileMapLayer

# Visual-only ground tiles. Five types, generated as a solid-color atlas at runtime
# so no art assets are needed. Step 1 lays down a basic distribution (street base,
# sidewalk grid, rubble/dirt edges, scattered vegetation); neighborhood structure
# is layered on in a later step.

const TILE_PX := 32
const MAP_TILES := 128

const STREET := 0
const SIDEWALK := 1
const RUBBLE := 2
const VEGETATION := 3
const DIRT := 4

const TILE_COLORS := [
	Color("3a3a3a"),  # street
	Color("4a4a4a"),  # sidewalk
	Color("2a2520"),  # rubble
	Color("3a4a35"),  # vegetation
	Color("4a3a30"),  # dirt
]

const EDGE_MARGIN := 6


func _ready() -> void:
	_build_tileset()
	_populate()


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
	var is_edge: bool = x < EDGE_MARGIN or y < EDGE_MARGIN or x >= MAP_TILES - EDGE_MARGIN or y >= MAP_TILES - EDGE_MARGIN
	if is_edge:
		return RUBBLE if (x + y) % 5 == 0 else DIRT
	if x % 16 == 0 or y % 16 == 0:
		return SIDEWALK
	if rng.randf() < 0.05:
		return VEGETATION
	return STREET
