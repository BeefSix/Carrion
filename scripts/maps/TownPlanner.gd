class_name TownPlanner
extends RefCounted

# Process-based map generation. The 12-step pipeline from the master spec:
#
#   1. Place anchor points (named destinations the town exists to serve)
#   2. Generate the primary road network (connects anchors)
#   3. Plat the lots (parcels between roads, with frontage + depth + zone)
#   4. Place buildings on lots (with setback + facing)
#   5. Fill lot spaces (yards, driveways, parking around buildings)
#   6. Add alleys (between paired rows of lots)
#   7. Apply wilderness edge gradient (outer 16 tiles fade to vegetation)
#   8. Add variation (vacant lots, damaged buildings, small parks)
#   9. Compute per-tile affordances (5 properties for unit AI)
#  10. Place player spawn clear zones (16x16 around each spawn anchor)
#  11. Mark infested buildings with zombie spawn profiles
#  12. Final validation + cleanup
#
# Each step is a separate function. Each step's output becomes the input to
# the next. The spec is explicit: do not optimize across steps. The order
# is the design. Towns are built sequentially; the spatial logic that makes
# a map feel like a town emerges from each step constraining the next.
#
# Usage:
#   var planner := TownPlanner.new()
#   var data := planner.plan_town()
#   # data is a Dictionary with keys: anchors, roads, lots, buildings,
#   # alleys, tile_grid, affordances, spawn_zones, lootables.

const MAP_TILES := 192

# Tile palette indices (matched to GroundTiles atlas slots).
const TILE_MAIN_ROAD := 0
const TILE_SIDEWALK := 1
const TILE_SECONDARY_ROAD := 2
const TILE_SIDE_STREET := 3
const TILE_PARKING_LOT := 4
const TILE_YARD := 5
const TILE_BARE_GROUND := 6
const TILE_DIRT_ROAD := 7
const TILE_VEGETATION := 8
const TILE_RUBBLE := 9

# Anchor positions (tile coords). Wilderness edge points come from the four
# cardinal map edges where the main roads exit.
const ANCHOR_SPAWN_NW := Vector2i(16, 16)
const ANCHOR_SPAWN_NE := Vector2i(176, 16)
const ANCHOR_SPAWN_SE := Vector2i(176, 176)
const ANCHOR_SPAWN_SW := Vector2i(16, 176)
const ANCHOR_DOWNTOWN := Vector2i(96, 96)
const ANCHOR_INDUSTRIAL := Vector2i(32, 160)
const ANCHOR_MEDICAL := Vector2i(160, 48)

# Road dimensions.
const PRIMARY_ROAD_HALFWIDTH := 1   # produces 4-tile-wide road (centerlines test abs <= 1 -> spans 3, +1 for second center = 4)
const SECONDARY_ROAD_HALFWIDTH := 0  # produces 2-tile-wide road
const SIDEWALK_BAND := 1             # tiles of sidewalk flanking primary roads

# Zone classification anchors. Used by step 3 to assign lot zones based on
# road position. Zone = which quadrant the road sits in.
const ZONE_RESIDENTIAL_NW := "residential_nw"
const ZONE_RESIDENTIAL_SE := "residential_se"
const ZONE_RESIDENTIAL_NE := "residential_ne"  # contested with medical
const ZONE_RESIDENTIAL_SW := "residential_sw"  # contested with industrial
const ZONE_DOWNTOWN := "downtown"
const ZONE_INDUSTRIAL := "industrial"
const ZONE_MEDICAL := "medical"

# Lot platting rules per zone (frontage/depth/spacing in tiles).
const LOT_RULES := {
	"residential_nw": { "frontage_min": 6, "frontage_max": 10, "depth_min": 10, "depth_max": 14, "spacing": 2 },
	"residential_ne": { "frontage_min": 6, "frontage_max": 10, "depth_min": 10, "depth_max": 14, "spacing": 2 },
	"residential_sw": { "frontage_min": 6, "frontage_max": 10, "depth_min": 10, "depth_max": 14, "spacing": 2 },
	"residential_se": { "frontage_min": 6, "frontage_max": 10, "depth_min": 10, "depth_max": 14, "spacing": 2 },
	"downtown":       { "frontage_min": 8, "frontage_max": 12, "depth_min": 8,  "depth_max": 12, "spacing": 0 },
	"industrial":     { "frontage_min": 16,"frontage_max": 24, "depth_min": 16, "depth_max": 24, "spacing": 5 },
	"medical":        { "frontage_min": 12,"frontage_max": 16, "depth_min": 12, "depth_max": 16, "spacing": 5 },
}

var _rng: RandomNumberGenerator


func plan_town(seed_value: int = 1) -> Dictionary:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	var data: Dictionary = {}
	data["anchors"] = step_1_anchors()
	data["roads"] = step_2_roads(data["anchors"])
	data["lots"] = step_3_lots(data["roads"])
	# Steps 4-12 stubbed; phases 2-4 implement.
	data["buildings"] = []
	data["alleys"] = []
	data["affordances"] = []
	data["spawn_zones"] = []
	data["lootables"] = []

	# Build the tile grid from roads + lots so GroundTiles has something to
	# paint. Later steps overwrite/extend this grid.
	data["tile_grid"] = _build_tile_grid(data["roads"], data["lots"])
	return data


# ---------------------------------------------------------------------
# Step 1 - anchors
# ---------------------------------------------------------------------
# The destinations the town's road network will connect. Roads exist to
# reach these points; without anchors, there's no reason for any layout.
func step_1_anchors() -> Array:
	return [
		{ "name": "spawn_nw",   "tile": ANCHOR_SPAWN_NW,   "kind": "spawn" },
		{ "name": "spawn_ne",   "tile": ANCHOR_SPAWN_NE,   "kind": "spawn" },
		{ "name": "spawn_se",   "tile": ANCHOR_SPAWN_SE,   "kind": "spawn" },
		{ "name": "spawn_sw",   "tile": ANCHOR_SPAWN_SW,   "kind": "spawn" },
		{ "name": "downtown",   "tile": ANCHOR_DOWNTOWN,   "kind": "downtown" },
		{ "name": "industrial", "tile": ANCHOR_INDUSTRIAL, "kind": "industrial" },
		{ "name": "medical",    "tile": ANCHOR_MEDICAL,    "kind": "medical" },
		# Wilderness edge exits - 4 cardinals where the main roads leave the map.
		{ "name": "edge_n", "tile": Vector2i(96, 0),   "kind": "edge_exit" },
		{ "name": "edge_s", "tile": Vector2i(96, 192), "kind": "edge_exit" },
		{ "name": "edge_e", "tile": Vector2i(192, 96), "kind": "edge_exit" },
		{ "name": "edge_w", "tile": Vector2i(0, 96),   "kind": "edge_exit" },
	]


# ---------------------------------------------------------------------
# Step 2 - primary + secondary road network
# ---------------------------------------------------------------------
# Roads connect anchors. The cross-shaped main road network passes through
# downtown and exits all four map edges. Secondary roads branch off the
# mains to reach each spawn corner and provide interior neighborhood access.
func step_2_roads(_anchors: Array) -> Array:
	var roads: Array = []

	# Main horizontal (y = 96) and main vertical (x = 96), 4 tiles wide,
	# full map length. These connect downtown to all four edge anchors.
	roads.append(_make_road("h", 96, 0, MAP_TILES, "primary"))
	roads.append(_make_road("v", 96, 0, MAP_TILES, "primary"))

	# Connector secondaries from the main roads to each spawn corner.
	# Each spawn is at tile 16 / 176; the main roads pass at tile 96.
	# Spawn NW (16, 16): branch off horizontal main at x=16, north to y=16.
	roads.append(_make_road("v", 16, 0, 96, "secondary"))
	# Spawn NE (176, 16): branch off horizontal main at x=176, north to y=16.
	roads.append(_make_road("v", 176, 0, 96, "secondary"))
	# Spawn SW (16, 176): branch off horizontal main at x=16, south to y=176.
	roads.append(_make_road("v", 16, 96, MAP_TILES, "secondary"))
	# Spawn SE (176, 176): branch off horizontal main at x=176, south to y=176.
	roads.append(_make_road("v", 176, 96, MAP_TILES, "secondary"))

	# Interior subdivision secondaries (residential neighborhood streets).
	# NW residential block - two cross streets at y=32 and y=72, plus a
	# north-south interior at x=48.
	roads.append(_make_road("h", 32, 16, 96, "secondary"))
	roads.append(_make_road("h", 72, 16, 96, "secondary"))
	roads.append(_make_road("v", 48, 16, 96, "secondary"))

	# NE quadrant (residential + medical anchor at 160, 48).
	roads.append(_make_road("h", 32, 96, MAP_TILES - 16, "secondary"))
	roads.append(_make_road("h", 72, 96, MAP_TILES - 16, "secondary"))
	roads.append(_make_road("v", 144, 16, 96, "secondary"))

	# SW quadrant (residential + industrial anchor at 32, 160).
	roads.append(_make_road("h", 120, 16, 96, "secondary"))
	roads.append(_make_road("h", 160, 16, 96, "secondary"))
	roads.append(_make_road("v", 48, 96, MAP_TILES - 16, "secondary"))

	# SE residential block.
	roads.append(_make_road("h", 120, 96, MAP_TILES - 16, "secondary"))
	roads.append(_make_road("h", 160, 96, MAP_TILES - 16, "secondary"))
	roads.append(_make_road("v", 144, 96, MAP_TILES - 16, "secondary"))

	return roads


func _make_road(axis: String, center: int, from_pos: int, to_pos: int, type_str: String) -> Dictionary:
	return {
		"axis": axis,
		"center": center,
		"from": from_pos,
		"to": to_pos,
		"type": type_str,
	}


# ---------------------------------------------------------------------
# Step 3 - lot platting
# ---------------------------------------------------------------------
# For each road, walk along its frontage strips (the tiles immediately
# adjacent to the road on each side) and carve out lots. Each lot is a
# rectangle with the road-facing edge as its frontage and the perpendicular
# direction as its depth. Lots terminate when they would overlap another
# lot, cross a road, or run out of zone-appropriate territory.
func step_3_lots(roads: Array) -> Array:
	var lots: Array = []
	# Track occupancy with a 192x192 grid - 0 = free, 1 = road or sidewalk,
	# 2 = lot. Lots can't be placed on occupied tiles.
	var occupancy := _build_road_occupancy_grid(roads)

	# Plat each secondary road's frontage. Primary roads carry commercial
	# downtown lots; the rest are residential / industrial / medical based
	# on the road's quadrant.
	for road in roads:
		if road["type"] == "primary":
			# Only the downtown portion of the primary roads gets commercial
			# lots. Skip the wilderness extensions.
			_plat_road_frontage(road, lots, occupancy, "primary")
		else:
			_plat_road_frontage(road, lots, occupancy, "secondary")
	return lots


func _build_road_occupancy_grid(roads: Array) -> PackedByteArray:
	# 0 = free, 1 = road/sidewalk (no lot allowed), 2 = lot (filled later).
	var grid := PackedByteArray()
	grid.resize(MAP_TILES * MAP_TILES)
	for road in roads:
		var half: int = PRIMARY_ROAD_HALFWIDTH if road["type"] == "primary" else SECONDARY_ROAD_HALFWIDTH
		var sidewalk: int = SIDEWALK_BAND if road["type"] == "primary" else 0
		var total_half: int = half + sidewalk + 1  # +1 covers the "second centerline" tile in 4-wide roads
		if road["axis"] == "h":
			var lo: int = max(0, road["from"])
			var hi: int = min(MAP_TILES - 1, road["to"] - 1)
			for x in range(lo, hi + 1):
				for dy in range(-total_half, total_half + 2):
					var y: int = road["center"] + dy
					if y >= 0 and y < MAP_TILES:
						grid[x + y * MAP_TILES] = 1
		else:
			var lo2: int = max(0, road["from"])
			var hi2: int = min(MAP_TILES - 1, road["to"] - 1)
			for y in range(lo2, hi2 + 1):
				for dx in range(-total_half, total_half + 2):
					var x: int = road["center"] + dx
					if x >= 0 and x < MAP_TILES:
						grid[x + y * MAP_TILES] = 1
	return grid


func _plat_road_frontage(road: Dictionary, lots: Array, occupancy: PackedByteArray, road_class: String) -> void:
	# For each side of the road, walk the frontage and carve lots. The
	# frontage strip sits just outside the sidewalk band; lot depth extends
	# further outward.
	var half: int = PRIMARY_ROAD_HALFWIDTH if road["type"] == "primary" else SECONDARY_ROAD_HALFWIDTH
	var sidewalk: int = SIDEWALK_BAND if road["type"] == "primary" else 0
	var setback: int = half + sidewalk + 2  # frontage strip starts 1 tile outside sidewalk

	# Two sides of the road: positive offset, negative offset.
	for side_sign in [-1, 1]:
		var strip_offset: int = side_sign * setback
		_walk_strip(road, lots, occupancy, strip_offset, side_sign, road_class)


func _walk_strip(road: Dictionary, lots: Array, occupancy: PackedByteArray, strip_offset: int, side_sign: int, road_class: String) -> void:
	var axis: String = road["axis"]
	var center: int = road["center"]
	var lo: int = road["from"]
	var hi: int = road["to"]

	# Walk along the road; cursor advances by lot frontage + spacing each
	# iteration. Skip the road's first/last 6 tiles (corner clearance).
	var cursor: int = lo + 6
	var stop: int = hi - 6
	while cursor < stop:
		var zone := _zone_at_strip_position(axis, center, cursor, strip_offset, road_class)
		if zone == "":
			cursor += 1
			continue
		var rules: Dictionary = LOT_RULES[zone]
		var frontage: int = _rng.randi_range(rules["frontage_min"], rules["frontage_max"])
		var depth: int = _rng.randi_range(rules["depth_min"], rules["depth_max"])
		# Build lot rect. Frontage runs ALONG the road axis; depth runs
		# perpendicular AWAY from the road.
		var lot_rect: Rect2i
		var frontage_dir: Vector2i
		if axis == "h":
			# Road runs east-west. Frontage = x, depth = y.
			var y_start: int = center + strip_offset if side_sign > 0 else center + strip_offset - depth + 1
			lot_rect = Rect2i(cursor, y_start, frontage, depth)
			frontage_dir = Vector2i(0, -side_sign)  # faces the road
		else:
			# Road runs north-south. Frontage = y, depth = x.
			var x_start: int = center + strip_offset if side_sign > 0 else center + strip_offset - depth + 1
			lot_rect = Rect2i(x_start, cursor, depth, frontage)
			frontage_dir = Vector2i(-side_sign, 0)
		if _lot_valid(lot_rect, occupancy):
			_mark_lot_occupied(lot_rect, occupancy)
			lots.append({
				"rect": lot_rect,
				"frontage_dir": frontage_dir,
				"zone": zone,
			})
			cursor += frontage + rules["spacing"]
		else:
			cursor += 1


func _zone_at_strip_position(axis: String, center: int, cursor: int, strip_offset: int, road_class: String) -> String:
	# Determine which zone this lot would belong to based on the strip
	# tile's map position. Quadrant logic with anchor proximity for
	# industrial / medical.
	var tx: int
	var ty: int
	if axis == "h":
		tx = cursor
		ty = center + strip_offset
	else:
		tx = center + strip_offset
		ty = cursor

	# Out-of-bounds or wilderness edge - no lot.
	if tx < 16 or tx >= MAP_TILES - 16 or ty < 16 or ty >= MAP_TILES - 16:
		return ""

	# Downtown commercial - within 16 tiles of the downtown anchor on a
	# primary road only.
	if road_class == "primary":
		var dx: int = tx - ANCHOR_DOWNTOWN.x
		var dy: int = ty - ANCHOR_DOWNTOWN.y
		if abs(dx) <= 18 and abs(dy) <= 18:
			return ZONE_DOWNTOWN
		# Primary roads outside downtown don't get lots - they're feeders.
		return ""

	# Secondary roads in NE quadrant near medical anchor - medical zone.
	if tx >= 128 and ty <= 80:
		var d_med: int = abs(tx - ANCHOR_MEDICAL.x) + abs(ty - ANCHOR_MEDICAL.y)
		if d_med <= 40:
			return ZONE_MEDICAL

	# Secondary roads in SW quadrant near industrial anchor - industrial zone.
	if tx <= 64 and ty >= 128:
		var d_ind: int = abs(tx - ANCHOR_INDUSTRIAL.x) + abs(ty - ANCHOR_INDUSTRIAL.y)
		if d_ind <= 40:
			return ZONE_INDUSTRIAL

	# Default: residential, by quadrant.
	if tx < 96 and ty < 96:
		return ZONE_RESIDENTIAL_NW
	if tx >= 96 and ty < 96:
		return ZONE_RESIDENTIAL_NE
	if tx < 96 and ty >= 96:
		return ZONE_RESIDENTIAL_SW
	return ZONE_RESIDENTIAL_SE


func _lot_valid(rect: Rect2i, occupancy: PackedByteArray) -> bool:
	if rect.position.x < 0 or rect.position.y < 0:
		return false
	if rect.position.x + rect.size.x > MAP_TILES:
		return false
	if rect.position.y + rect.size.y > MAP_TILES:
		return false
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if occupancy[x + y * MAP_TILES] != 0:
				return false
	return true


func _mark_lot_occupied(rect: Rect2i, occupancy: PackedByteArray) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			occupancy[x + y * MAP_TILES] = 2


# ---------------------------------------------------------------------
# Tile grid builder
# ---------------------------------------------------------------------
# Compose the final 192x192 tile grid from the road network + lot data.
# Wilderness/edges, lot fill, and post-process steps are layered on later.
func _build_tile_grid(roads: Array, lots: Array) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(MAP_TILES * MAP_TILES)
	# Default fill: bare ground.
	for i in range(grid.size()):
		grid[i] = TILE_BARE_GROUND

	# Paint lots first - their interior tiles will be overwritten by roads
	# (roads are drawn on top to ensure they win at intersections).
	for lot in lots:
		var interior_tile := _interior_tile_for_zone(lot["zone"])
		var rect: Rect2i = lot["rect"]
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
					grid[x + y * MAP_TILES] = interior_tile

	# Paint roads + sidewalks. Primary roads have 4-tile bodies + 1-tile
	# sidewalk band on each side.
	for road in roads:
		var half: int = PRIMARY_ROAD_HALFWIDTH if road["type"] == "primary" else SECONDARY_ROAD_HALFWIDTH
		var sidewalk: int = SIDEWALK_BAND if road["type"] == "primary" else 0
		var body_tile := TILE_MAIN_ROAD if road["type"] == "primary" else TILE_SECONDARY_ROAD
		if road["axis"] == "h":
			for x in range(max(0, road["from"]), min(MAP_TILES, road["to"])):
				for dy in range(-half - 1, half + 2):  # the "+1" half-tile asymmetry produces 4-wide
					var y: int = road["center"] + dy
					if y >= 0 and y < MAP_TILES:
						grid[x + y * MAP_TILES] = body_tile
				if sidewalk > 0:
					for dy in [-half - 2, half + 2]:
						var ys: int = road["center"] + dy
						if ys >= 0 and ys < MAP_TILES:
							grid[x + ys * MAP_TILES] = TILE_SIDEWALK
		else:
			for y in range(max(0, road["from"]), min(MAP_TILES, road["to"])):
				for dx in range(-half - 1, half + 2):
					var x: int = road["center"] + dx
					if x >= 0 and x < MAP_TILES:
						grid[x + y * MAP_TILES] = body_tile
				if sidewalk > 0:
					for dx in [-half - 2, half + 2]:
						var xs: int = road["center"] + dx
						if xs >= 0 and xs < MAP_TILES:
							grid[xs + y * MAP_TILES] = TILE_SIDEWALK

	return grid


func _interior_tile_for_zone(zone: String) -> int:
	# Default interior fill per zone. Later steps overlay building footprints
	# (Step 4), driveways (Step 5), etc. on top.
	match zone:
		ZONE_DOWNTOWN:
			return TILE_PARKING_LOT
		ZONE_INDUSTRIAL:
			return TILE_PARKING_LOT
		ZONE_MEDICAL:
			return TILE_PARKING_LOT
		_:
			return TILE_YARD  # all residential variants


# ---------------------------------------------------------------------
# Step stubs - implemented in subsequent phases
# ---------------------------------------------------------------------
func step_4_buildings_on_lots(_lots: Array) -> Array:
	return []


func step_5_fill_lot_spaces(_lots: Array, _buildings: Array, _grid: PackedByteArray) -> void:
	pass


func step_6_alleys(_lots: Array) -> Array:
	return []


func step_7_wilderness_gradient(_grid: PackedByteArray) -> void:
	pass


func step_8_variation(_lots: Array, _buildings: Array) -> void:
	pass


func step_9_affordances(_grid: PackedByteArray, _buildings: Array) -> Array:
	return []


func step_10_spawn_clear_zones(_lots: Array, _buildings: Array) -> Array:
	return []


func step_11_lootable_markers(_buildings: Array) -> Array:
	return []


func step_12_validate(_data: Dictionary) -> Array:
	return []
