extends TileMapLayer

# Ground rendering for the PZ-style small-town layout. 10-tile palette per the
# town-layout spec; iso 4:3 tile shape so each tile renders as a 64x48 diamond
# aligned with the rest of the iso world.
#
# Spatial structure:
#   - 4-tile-wide main roads cross at the map center, forming downtown's
#     four-way intersection.
#   - 1-tile sidewalk band on each side of every main road.
#   - 2-tile-wide secondary roads branch off the mains in each quadrant,
#     leading into residential / medical / industrial zones.
#   - Zone interiors: yard (residential), parking lot (commercial / industrial /
#     medical), bare ground (transitional space).
#   - Wilderness edge band fades from town into vegetation+dirt over the outer
#     16 tiles; outermost 8 tiles are wilderness only.
#
# Buildings are placed in Main._spawn_lootables() with zone-appropriate
# positions; this script paints the substrate they sit on.

const TILE_W := 64
const TILE_H := 48
const MAP_TILES := 192

# Tile palette (atlas column indices).
const MAIN_ROAD := 0       # 4-tile-wide main road surface
const SIDEWALK := 1        # flanking the main roads
const SECONDARY_ROAD := 2  # 2-tile-wide neighborhood streets
const SIDE_STREET := 3     # 1-tile alleys, dirt streets
const PARKING_LOT := 4     # commercial / industrial / medical lots
const YARD := 5            # residential grass between houses
const BARE_GROUND := 6     # default transitional ground
const DIRT_ROAD := 7       # rural connection, wilderness
const VEGETATION := 8      # parks, wilderness, overgrowth
const RUBBLE := 9          # destroyed areas, edge band

const TILE_COLORS := [
	Color("2a2a2a"),  # main road (very dark gray)
	Color("5a5a5a"),  # sidewalk (medium gray)
	Color("3a3a3a"),  # secondary road (dark gray)
	Color("2f2820"),  # side street (dark gray-brown, unpaved-ish)
	Color("404040"),  # parking lot (gray)
	Color("455040"),  # yard / grass (faded green)
	Color("4a4035"),  # bare ground (faded brown)
	Color("4a3a30"),  # dirt road (warm brown)
	Color("3a4a35"),  # vegetation (desaturated olive)
	Color("2a2520"),  # rubble (dark warm gray-brown)
]

# Outermost 8 tiles = pure wilderness (rubble / vegetation mix).
# Tiles 8..15 = wilderness band (vegetation + dirt blend).
# Tiles 16..23 = wilderness-to-town transition.
const RUBBLE_EDGE := 8
const WILDERNESS_BAND := 24

# Main road centerlines (4 tiles wide = halfwidth 1.5 each side, but we use
# integer test "abs(x - lane) <= 1" -> 4-tile wide).
const MAIN_ROAD_X := 96
const MAIN_ROAD_Y := 96
const MAIN_HALFWIDTH := 1     # produces a 4-tile-wide band (x-1, x, x+1 -> 3) +1 -> 4 with the second center
const SIDEWALK_WIDTH := 1     # 1 tile on each side of main road

# Secondary roads (2 tiles wide). Each entry is an orthogonal segment.
# axis: "h" (horizontal, runs across x at fixed y) or "v" (vertical at fixed x).
# center: the tile coord of the road's centerline.
# from / to: extent along the road's axis (inclusive).
const SECONDARY_ROADS := [
	# NW residential block - serves player 1's area + interior streets
	{ "axis": "v", "center": 32, "from": 20, "to": 92 },
	{ "axis": "v", "center": 56, "from": 20, "to": 92 },
	{ "axis": "h", "center": 32, "from": 20, "to": 92 },
	{ "axis": "h", "center": 56, "from": 20, "to": 92 },

	# NE medical/security block
	{ "axis": "v", "center": 156, "from": 20, "to": 92 },
	{ "axis": "h", "center": 32, "from": 100, "to": 172 },

	# SW industrial block (sparser - one access road)
	{ "axis": "h", "center": 156, "from": 20, "to": 92 },
	{ "axis": "v", "center": 32, "from": 100, "to": 172 },

	# SE residential block - player 2's area + interior streets
	{ "axis": "v", "center": 136, "from": 100, "to": 172 },
	{ "axis": "v", "center": 160, "from": 100, "to": 172 },
	{ "axis": "h", "center": 136, "from": 100, "to": 172 },
	{ "axis": "h", "center": 160, "from": 100, "to": 172 },
]

# Zone definitions (tile rect) - drive interior ground tile painting.
const ZONE_DOWNTOWN := { "x": 84, "y": 84, "w": 24, "h": 24 }
const ZONE_NW_RES := { "x": 16, "y": 16, "w": 76, "h": 76 }
const ZONE_NE_MED := { "x": 100, "y": 16, "w": 76, "h": 76 }
const ZONE_SW_IND := { "x": 16, "y": 100, "w": 76, "h": 76 }
const ZONE_SE_RES := { "x": 100, "y": 100, "w": 76, "h": 76 }


func _ready() -> void:
	add_to_group("ground_tiles")
	_build_tileset()
	_populate()


func get_tile_type_at(world_pos: Vector2) -> int:
	var tile_x: int = int(world_pos.x / IsoView.TILE_WORLD_PX)
	var tile_y: int = int(world_pos.y / IsoView.TILE_WORLD_PX)
	if tile_x < 0 or tile_y < 0 or tile_x >= MAP_TILES or tile_y >= MAP_TILES:
		return -1
	var atlas := get_cell_atlas_coords(Vector2i(tile_x, tile_y))
	return atlas.x


func _build_tileset() -> void:
	# Diamond-masked atlas. TILE_W x TILE_H per tile, transparent outside the
	# 2:1 diamond shape (Godot's iso TileMapLayer handles positioning; we
	# control texture appearance).
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


func _populate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			set_cell(Vector2i(x, y), 0, Vector2i(_tile_type_at(x, y, rng), 0))


func _tile_type_at(x: int, y: int, rng: RandomNumberGenerator) -> int:
	# Outermost 8 tiles: pure wilderness with rubble accents.
	if _is_rubble_edge(x, y):
		if (x + y) % 3 == 0:
			return RUBBLE
		return VEGETATION
	# Tiles 8..15: wilderness band - vegetation, dirt, occasional rubble.
	if _is_wilderness_band(x, y):
		var roll: float = rng.randf()
		if roll < 0.35:
			return VEGETATION
		if roll < 0.55:
			return DIRT_ROAD
		return BARE_GROUND
	# Roads (main / sidewalk / secondary) take priority over zone interior.
	var road := _road_at(x, y)
	if road != -1:
		return road
	# Zone-specific interior fill.
	return _zone_fill_at(x, y, rng)


func _is_rubble_edge(x: int, y: int) -> bool:
	return x < RUBBLE_EDGE or y < RUBBLE_EDGE or x >= MAP_TILES - RUBBLE_EDGE or y >= MAP_TILES - RUBBLE_EDGE


func _is_wilderness_band(x: int, y: int) -> bool:
	return x < WILDERNESS_BAND or y < WILDERNESS_BAND or x >= MAP_TILES - WILDERNESS_BAND or y >= MAP_TILES - WILDERNESS_BAND


func _road_at(x: int, y: int) -> int:
	# Main road bodies first - 4 tiles centered on MAIN_ROAD_X/Y.
	# Test uses two centerlines effectively: abs(x - center) <= 1 spans 3
	# tiles; we want 4 so check abs(x - (center + 0.5)) <= 1.5 via integer
	# range x in [center-1, center+2].
	if y >= MAIN_ROAD_Y - 1 and y <= MAIN_ROAD_Y + 2:
		return MAIN_ROAD
	if x >= MAIN_ROAD_X - 1 and x <= MAIN_ROAD_X + 2:
		return MAIN_ROAD
	# Sidewalks - 1 tile band on each side of every main road body.
	if y == MAIN_ROAD_Y - 2 or y == MAIN_ROAD_Y + 3:
		return SIDEWALK
	if x == MAIN_ROAD_X - 2 or x == MAIN_ROAD_X + 3:
		return SIDEWALK
	# Secondary roads.
	for seg in SECONDARY_ROADS:
		if seg["axis"] == "h":
			# Horizontal segment: 2 tiles wide centered on seg.center, extending
			# from seg.from to seg.to in x.
			var c: int = seg["center"]
			if y >= c and y <= c + 1 and x >= seg["from"] and x <= seg["to"]:
				return SECONDARY_ROAD
		else:
			var c2: int = seg["center"]
			if x >= c2 and x <= c2 + 1 and y >= seg["from"] and y <= seg["to"]:
				return SECONDARY_ROAD
	return -1


func _zone_fill_at(x: int, y: int, rng: RandomNumberGenerator) -> int:
	# Downtown - commercial parking lots fill the dense central block.
	if _in_zone(x, y, ZONE_DOWNTOWN):
		return PARKING_LOT
	# Residential interiors - mostly yards with occasional bare/vegetation.
	if _in_zone(x, y, ZONE_NW_RES) or _in_zone(x, y, ZONE_SE_RES):
		var roll: float = rng.randf()
		if roll < 0.08:
			return VEGETATION
		if roll < 0.18:
			return BARE_GROUND
		return YARD
	# Medical / security - institutional parking around the buildings.
	if _in_zone(x, y, ZONE_NE_MED):
		return PARKING_LOT
	# Industrial - parking/loading lots.
	if _in_zone(x, y, ZONE_SW_IND):
		return PARKING_LOT
	# Open ground between zones.
	var roll2: float = rng.randf()
	if roll2 < 0.03:
		return VEGETATION
	return BARE_GROUND


func _in_zone(x: int, y: int, zone: Dictionary) -> bool:
	return x >= zone["x"] and x < zone["x"] + zone["w"] and y >= zone["y"] and y < zone["y"] + zone["h"]
