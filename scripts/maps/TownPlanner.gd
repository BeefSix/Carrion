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
const ANCHOR_SPAWN_NW := Vector2i(24, 24)
const ANCHOR_SPAWN_NE := Vector2i(168, 24)
const ANCHOR_SPAWN_SE := Vector2i(168, 168)
const ANCHOR_SPAWN_SW := Vector2i(24, 168)
const ANCHOR_DOWNTOWN := Vector2i(96, 96)
const ANCHOR_INDUSTRIAL := Vector2i(32, 160)
const ANCHOR_MEDICAL := Vector2i(160, 48)

# Road dimensions (in tiles). 1 tile ~= 2 meters per the scale anchor:
#   primary 4-wide  = 8 m (two-lane + sidewalks ok)
#   secondary 3-wide = 6 m (real residential street width)
#   alley 2-wide    = 4 m (real service alley)
const PRIMARY_ROAD_WIDTH := 4
const SECONDARY_ROAD_WIDTH := 3
const ALLEY_WIDTH := 2
const SIDEWALK_BAND := 1            # tiles of sidewalk flanking primary roads

# Zone classification anchors. Used by step 3 to assign lot zones based on
# road position. Zone = which quadrant the road sits in.
const ZONE_RESIDENTIAL_NW := "residential_nw"
const ZONE_RESIDENTIAL_SE := "residential_se"
const ZONE_RESIDENTIAL_NE := "residential_ne"  # contested with medical
const ZONE_RESIDENTIAL_SW := "residential_sw"  # contested with industrial
const ZONE_DOWNTOWN := "downtown"
const ZONE_INDUSTRIAL := "industrial"
const ZONE_MEDICAL := "medical"

# Lot platting rules per zone. Frontage / depth / spacing in tiles. Sizes
# tuned so each zone's lots fit the scale-adjusted building footprints
# (residential 3x3/4x3/4x4, commercial up to 8x6, industrial 8x8 to 12x12,
# medical 6x6 to 8x8) with appropriate setback. Per spec: residential lots
# 6-10 frontage / 10-14 depth (small pre-war / European town density);
# industrial / medical bumped up so 10x10+ buildings have setback room.
const LOT_RULES := {
	"residential_nw": { "frontage_min": 8, "frontage_max": 12, "depth_min": 12, "depth_max": 16, "spacing": 2 },
	"residential_ne": { "frontage_min": 8, "frontage_max": 12, "depth_min": 12, "depth_max": 16, "spacing": 2 },
	"residential_sw": { "frontage_min": 8, "frontage_max": 12, "depth_min": 12, "depth_max": 16, "spacing": 2 },
	"residential_se": { "frontage_min": 8, "frontage_max": 12, "depth_min": 12, "depth_max": 16, "spacing": 2 },
	"downtown":       { "frontage_min": 10, "frontage_max": 14, "depth_min": 10, "depth_max": 14, "spacing": 0 },
	"industrial":     { "frontage_min": 22, "frontage_max": 30, "depth_min": 22, "depth_max": 30, "spacing": 5 },
	"medical":        { "frontage_min": 14, "frontage_max": 20, "depth_min": 14, "depth_max": 20, "spacing": 5 },
}

var _rng: RandomNumberGenerator


func plan_town(seed_value: int = 1) -> Dictionary:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	var data: Dictionary = {}
	data["anchors"] = step_1_anchors()
	data["roads"] = step_2_roads(data["anchors"])
	data["lots"] = step_3_lots(data["roads"])
	data["buildings"] = step_4_buildings_on_lots(data["lots"])
	# Build base tile grid (roads + lot fills) before step 5 overlays yards,
	# driveways, parking, and building footprint placeholders.
	data["tile_grid"] = _build_tile_grid(data["roads"], data["lots"])
	step_5_fill_lot_spaces(data["lots"], data["buildings"], data["tile_grid"])
	data["alleys"] = step_6_alleys(data["lots"])
	_paint_alleys(data["alleys"], data["tile_grid"])
	step_7_wilderness_gradient(data["tile_grid"])
	step_8_variation(data["lots"], data["buildings"], data["tile_grid"])
	data["spawn_zones"] = step_10_spawn_clear_zones(data["lots"], data["buildings"], data["tile_grid"])
	data["lootables"] = step_11_lootable_markers(data["buildings"])
	data["affordances"] = step_9_affordances(data["tile_grid"], data["buildings"])
	step_12_validate(data)
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


func _road_width(road: Dictionary) -> int:
	return PRIMARY_ROAD_WIDTH if road["type"] == "primary" else SECONDARY_ROAD_WIDTH


func _road_sidewalk(road: Dictionary) -> int:
	# Both primary and secondary roads get a 1-tile sidewalk flank now -
	# this is what visually defines the road as a feature (high-contrast
	# light gray sidewalk against the darker road body and the adjacent
	# yard/parking). Previously only primary roads got sidewalks, which
	# made secondary roads bleed into adjacent lots visually.
	return SIDEWALK_BAND


func _build_road_occupancy_grid(roads: Array) -> PackedByteArray:
	# 0 = free, 1 = road/sidewalk (no lot allowed), 2 = lot (filled later).
	var grid := PackedByteArray()
	grid.resize(MAP_TILES * MAP_TILES)
	for road in roads:
		var width: int = _road_width(road)
		var sidewalk: int = _road_sidewalk(road)
		# Half-extent from the centerline: for width=4 we want [-2..+1], for
		# width=3 we want [-1..+1], for width=2 we want [-1..0]. width/2
		# floors give us the "low" offset; "high" = width - low - 1.
		var low: int = width / 2
		var high: int = width - low - 1
		var min_offset: int = -low - sidewalk
		var max_offset: int = high + sidewalk
		if road["axis"] == "h":
			var lo: int = max(0, road["from"])
			var hi: int = min(MAP_TILES - 1, road["to"] - 1)
			for x in range(lo, hi + 1):
				for dy in range(min_offset, max_offset + 1):
					var y: int = road["center"] + dy
					if y >= 0 and y < MAP_TILES:
						grid[x + y * MAP_TILES] = 1
		else:
			var lo2: int = max(0, road["from"])
			var hi2: int = min(MAP_TILES - 1, road["to"] - 1)
			for y in range(lo2, hi2 + 1):
				for dx in range(min_offset, max_offset + 1):
					var x: int = road["center"] + dx
					if x >= 0 and x < MAP_TILES:
						grid[x + y * MAP_TILES] = 1
	return grid


func _plat_road_frontage(road: Dictionary, lots: Array, occupancy: PackedByteArray, road_class: String) -> void:
	# For each side of the road, walk the frontage and carve lots. The
	# frontage strip sits just outside the sidewalk band; lot depth extends
	# further outward.
	var width: int = _road_width(road)
	var sidewalk: int = _road_sidewalk(road)
	# Strip offset = halfwidth from centerline + sidewalk band + 1 (frontage
	# strip starts 1 tile outside the road footprint).
	var low: int = width / 2
	var high: int = width - low - 1
	# We want two separate offsets, one for each side, because of the
	# "second centerline" asymmetry for even widths.
	var offset_neg: int = -(low + sidewalk + 1)
	var offset_pos: int = high + sidewalk + 1
	_walk_strip(road, lots, occupancy, offset_neg, -1, road_class)
	_walk_strip(road, lots, occupancy, offset_pos, 1, road_class)


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
# Compose the base 192x192 tile grid from the road network + lot interiors.
# Step 5 (lot fill + driveways + building placeholders) overlays this.
func _build_tile_grid(roads: Array, lots: Array) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(MAP_TILES * MAP_TILES)
	for i in range(grid.size()):
		grid[i] = TILE_BARE_GROUND
	# Paint lots' interior fill first; roads then win at intersections.
	for lot in lots:
		var interior_tile := _interior_tile_for_zone(lot["zone"])
		var rect: Rect2i = lot["rect"]
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
					grid[x + y * MAP_TILES] = interior_tile
	# Paint roads (body + sidewalks for primary).
	for road in roads:
		var width: int = _road_width(road)
		var sidewalk: int = _road_sidewalk(road)
		var body_tile := TILE_MAIN_ROAD if road["type"] == "primary" else TILE_SECONDARY_ROAD
		var low: int = width / 2
		var high: int = width - low - 1
		if road["axis"] == "h":
			for x in range(max(0, road["from"]), min(MAP_TILES, road["to"])):
				for dy in range(-low, high + 1):
					var y: int = road["center"] + dy
					if y >= 0 and y < MAP_TILES:
						grid[x + y * MAP_TILES] = body_tile
				if sidewalk > 0:
					for dy in [-low - 1, high + 1]:
						var ys: int = road["center"] + dy
						if ys >= 0 and ys < MAP_TILES:
							grid[x + ys * MAP_TILES] = TILE_SIDEWALK
		else:
			for y in range(max(0, road["from"]), min(MAP_TILES, road["to"])):
				for dx in range(-low, high + 1):
					var x: int = road["center"] + dx
					if x >= 0 and x < MAP_TILES:
						grid[x + y * MAP_TILES] = body_tile
				if sidewalk > 0:
					for dx in [-low - 1, high + 1]:
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
# Step 4 - buildings on lots
# ---------------------------------------------------------------------
# Each lot gets one building, footprint and setback per zone rules.
# Building faces the lot's frontage_dir (which is the direction toward the
# road the lot fronts). Because every lot has exactly one frontage_dir
# inherited from its generating road in step 3, every building on the same
# side of the same road faces the same way - the watchlist failure mode
# "buildings facing inconsistent directions within a single row" is
# prevented by construction.
func step_4_buildings_on_lots(lots: Array) -> Array:
	var buildings: Array = []
	for lot in lots:
		var building := _place_building_on_lot(lot)
		if not building.is_empty():
			buildings.append(building)
	return buildings


func _place_building_on_lot(lot: Dictionary) -> Dictionary:
	var zone: String = lot["zone"]
	var rect: Rect2i = lot["rect"]
	var frontage_dir: Vector2i = lot["frontage_dir"]
	var spec := _building_spec_for_zone(zone)
	if spec.is_empty():
		return {}
	# Footprint is (along_road, perpendicular_to_road) - we rotate the
	# layout depending on whether the road is horizontal or vertical.
	var along: int = spec["width"]
	var perp: int = spec["depth"]
	var setback: int = spec["setback"]
	var bx: int = 0
	var by: int = 0
	var bw: int = 0
	var bh: int = 0
	if frontage_dir.y != 0:
		# Horizontal road - frontage axis is X, depth axis is Y.
		bw = along
		bh = perp
		bx = rect.position.x + int((rect.size.x - bw) / 2)
		if frontage_dir.y < 0:
			by = rect.position.y + setback
		else:
			by = rect.position.y + rect.size.y - setback - bh
	else:
		# Vertical road - frontage axis is Y, depth axis is X.
		bw = perp
		bh = along
		by = rect.position.y + int((rect.size.y - bh) / 2)
		if frontage_dir.x < 0:
			bx = rect.position.x + setback
		else:
			bx = rect.position.x + rect.size.x - setback - bw
	# Validate building fits inside the lot.
	if bx < rect.position.x or by < rect.position.y:
		return {}
	if bx + bw > rect.position.x + rect.size.x:
		return {}
	if by + bh > rect.position.y + rect.size.y:
		return {}
	return {
		"rect": Rect2i(bx, by, bw, bh),
		"facing": frontage_dir,
		"zone": zone,
	}


func _building_spec_for_zone(zone: String) -> Dictionary:
	# Returns {"width": int, "depth": int, "setback": int} where width is
	# the dimension along the road frontage and depth is into the lot.
	# Footprints scaled to the master spec's 1-tile = 2m anchor:
	#   residential 3x3 (6x6m) -> 4x4 (8x8m): real small-to-modest house
	#   commercial  4x3 (8x6m) -> 6x4 (12x8m): real storefront to mid shop
	#   industrial  8x8 (16x16m) -> 12x12 (24x24m): real warehouse
	#   medical/civic 6x6 (12x12m) -> 8x8 (16x16m): clinic / small police
	# Variation within a row breaks photocopy uniformity.
	match zone:
		ZONE_RESIDENTIAL_NW, ZONE_RESIDENTIAL_NE, ZONE_RESIDENTIAL_SE, ZONE_RESIDENTIAL_SW:
			var roll: float = _rng.randf()
			if roll < 0.4:
				return { "width": 3, "depth": 3, "setback": _rng.randi_range(2, 3) }
			elif roll < 0.75:
				return { "width": 4, "depth": 3, "setback": _rng.randi_range(2, 3) }
			else:
				return { "width": 4, "depth": 4, "setback": _rng.randi_range(2, 3) }
		ZONE_DOWNTOWN:
			var droll: float = _rng.randf()
			if droll < 0.5:
				return { "width": 4, "depth": 3, "setback": 0 }
			elif droll < 0.85:
				return { "width": 6, "depth": 4, "setback": 0 }
			else:
				return { "width": 8, "depth": 6, "setback": 0 }
		ZONE_INDUSTRIAL:
			var iroll: float = _rng.randf()
			if iroll < 0.5:
				return { "width": 8, "depth": 8, "setback": _rng.randi_range(4, 8) }
			elif iroll < 0.85:
				return { "width": 10, "depth": 10, "setback": _rng.randi_range(4, 8) }
			else:
				return { "width": 12, "depth": 12, "setback": _rng.randi_range(4, 8) }
		ZONE_MEDICAL:
			if _rng.randf() < 0.5:
				return { "width": 6, "depth": 6, "setback": _rng.randi_range(4, 6) }
			return { "width": 8, "depth": 8, "setback": _rng.randi_range(4, 6) }
	return {}


# ---------------------------------------------------------------------
# Step 5 - fill lot spaces
# ---------------------------------------------------------------------
# Paint the non-building portion of each lot with zone-appropriate tile
# types. Building footprints get TILE_RUBBLE as a placeholder so the
# pre-Lootable visual clearly shows lot/building/yard structure; once
# Step 11 spawns real Lootable instances they will visually cover the
# placeholder tiles.
func step_5_fill_lot_spaces(lots: Array, buildings: Array, grid: PackedByteArray) -> void:
	# Index buildings by their lot for quick lookup (matched by zone +
	# overlap; lots and buildings are parallel arrays in our pipeline so
	# we can pair them by index).
	for i in range(lots.size()):
		var lot: Dictionary = lots[i]
		if i >= buildings.size():
			continue
		var building: Dictionary = buildings[i]
		_fill_lot(lot, building, grid)


func _fill_lot(lot: Dictionary, building: Dictionary, grid: PackedByteArray) -> void:
	var lot_rect: Rect2i = lot["rect"]
	var zone: String = lot["zone"]
	var fill_tile := _lot_fill_tile_for_zone(zone)
	var building_rect: Rect2i = building.get("rect", Rect2i())
	# Paint the lot interior with the fill tile.
	for x in range(lot_rect.position.x, lot_rect.position.x + lot_rect.size.x):
		for y in range(lot_rect.position.y, lot_rect.position.y + lot_rect.size.y):
			if x < 0 or x >= MAP_TILES or y < 0 or y >= MAP_TILES:
				continue
			grid[x + y * MAP_TILES] = fill_tile
	# Paint the building footprint with a placeholder tile.
	if not building.is_empty():
		for x in range(building_rect.position.x, building_rect.position.x + building_rect.size.x):
			for y in range(building_rect.position.y, building_rect.position.y + building_rect.size.y):
				if x < 0 or x >= MAP_TILES or y < 0 or y >= MAP_TILES:
					continue
				grid[x + y * MAP_TILES] = TILE_RUBBLE  # placeholder for building footprint
	# Driveway: 1-tile-wide strip from the road to the building, only in
	# residential zones with setback > 0.
	if _is_residential(zone) and not building.is_empty():
		_paint_driveway(lot, building, grid)


func _lot_fill_tile_for_zone(zone: String) -> int:
	match zone:
		ZONE_DOWNTOWN:
			return TILE_SIDEWALK  # downtown buildings sit directly on sidewalk
		ZONE_INDUSTRIAL:
			return TILE_PARKING_LOT
		ZONE_MEDICAL:
			return TILE_PARKING_LOT
	return TILE_YARD  # residential default


func _is_residential(zone: String) -> bool:
	return zone == ZONE_RESIDENTIAL_NW or zone == ZONE_RESIDENTIAL_NE or zone == ZONE_RESIDENTIAL_SW or zone == ZONE_RESIDENTIAL_SE


func _paint_driveway(lot: Dictionary, building: Dictionary, grid: PackedByteArray) -> void:
	var lot_rect: Rect2i = lot["rect"]
	var building_rect: Rect2i = building["rect"]
	var frontage_dir: Vector2i = lot["frontage_dir"]
	# Driveway runs from the road edge of the lot to the road-facing edge
	# of the building. 1 tile wide, along the lot's frontage axis at the
	# building's edge.
	if frontage_dir.y != 0:
		# Horizontal road - driveway runs north-south on x = building edge x
		var driveway_x: int = building_rect.position.x  # left edge of building
		var y_start: int = 0
		var y_end: int = 0
		if frontage_dir.y < 0:
			y_start = lot_rect.position.y
			y_end = building_rect.position.y
		else:
			y_start = building_rect.position.y + building_rect.size.y
			y_end = lot_rect.position.y + lot_rect.size.y
		for y in range(y_start, y_end):
			if driveway_x >= 0 and driveway_x < MAP_TILES and y >= 0 and y < MAP_TILES:
				grid[driveway_x + y * MAP_TILES] = TILE_SIDE_STREET
	else:
		# Vertical road - driveway runs east-west
		var driveway_y: int = building_rect.position.y
		var x_start: int = 0
		var x_end: int = 0
		if frontage_dir.x < 0:
			x_start = lot_rect.position.x
			x_end = building_rect.position.x
		else:
			x_start = building_rect.position.x + building_rect.size.x
			x_end = lot_rect.position.x + lot_rect.size.x
		for x in range(x_start, x_end):
			if x >= 0 and x < MAP_TILES and driveway_y >= 0 and driveway_y < MAP_TILES:
				grid[x + driveway_y * MAP_TILES] = TILE_SIDE_STREET


# ---------------------------------------------------------------------
# Step 6 - alleys
# ---------------------------------------------------------------------
# 1-tile-wide dirt-road alleys between paired rows of residential lots
# (lots whose back edges face each other across a narrow gap). For this
# version we find pairs of horizontal residential roads close enough to
# have back-to-back lots between them, and paint an alley strip at the
# midpoint. Same for vertical road pairs.
func step_6_alleys(lots: Array) -> Array:
	var alleys: Array = []
	# Group residential lots by which road they front and their side.
	# Find pairs where back edges face each other.
	# Simplified: find horizontal alley opportunities (paired horizontal
	# roads with residential lots between them).
	var horizontal_back_pairs: Dictionary = {}  # key: (y_top, y_bot), value: [lots in pair]
	for lot in lots:
		if not _is_residential(lot["zone"]):
			continue
		var rect: Rect2i = lot["rect"]
		var frontage_dir: Vector2i = lot["frontage_dir"]
		if frontage_dir.y == 0:
			continue
		# Lot back edge is opposite the frontage direction.
		var back_y: int = 0
		if frontage_dir.y < 0:
			back_y = rect.position.y + rect.size.y  # south back edge
		else:
			back_y = rect.position.y  # north back edge
		# Place a row-key by approximate back_y (bucket by 4 tiles)
		var key: int = back_y / 4
		if not horizontal_back_pairs.has(key):
			horizontal_back_pairs[key] = []
		horizontal_back_pairs[key].append(lot)
	# For each cluster with 4+ lots, add an alley at the cluster's back_y.
	for key in horizontal_back_pairs.keys():
		var cluster: Array = horizontal_back_pairs[key]
		if cluster.size() < 4:
			continue
		# Sample roughly 50-60% of clusters get an alley (per spec).
		if _rng.randf() > 0.55:
			continue
		var back_y: int = key * 4 + 2  # approximate alley y
		var min_x: int = MAP_TILES
		var max_x: int = 0
		for lot in cluster:
			var r: Rect2i = lot["rect"]
			min_x = min(min_x, r.position.x)
			max_x = max(max_x, r.position.x + r.size.x)
		alleys.append({
			"axis": "h",
			"y": back_y,
			"from": min_x,
			"to": max_x,
		})
	return alleys


func _paint_alleys(alleys: Array, grid: PackedByteArray) -> void:
	# Alleys are ALLEY_WIDTH tiles wide (2 tiles = ~4 m, a real service alley).
	for a in alleys:
		if a["axis"] == "h":
			var y_center: int = a["y"]
			for dy in range(0, ALLEY_WIDTH):
				var y: int = y_center + dy
				if y < 0 or y >= MAP_TILES:
					continue
				for x in range(max(0, a["from"]), min(MAP_TILES, a["to"])):
					grid[x + y * MAP_TILES] = TILE_DIRT_ROAD
		else:
			var x_center: int = a["x"]
			for dx in range(0, ALLEY_WIDTH):
				var x: int = x_center + dx
				if x < 0 or x >= MAP_TILES:
					continue
				for y in range(max(0, a["from"]), min(MAP_TILES, a["to"])):
					grid[x + y * MAP_TILES] = TILE_DIRT_ROAD


# ---------------------------------------------------------------------
# Step 7 - wilderness edge gradient
# ---------------------------------------------------------------------
# Outer 16 tiles fade from town to wilderness. Gradient is gradual (not
# binary): density of vegetation rises and density of paved/yard tiles
# drops as distance from edge decreases. Watchlist item "hard binary
# cutoff" is the primary failure mode to avoid; we sample tile probabilities
# by distance instead of toggling at a single threshold.
#
# Zones:
#   distance 0..7  - pure wilderness (vegetation + dirt + occasional rubble)
#   distance 8..15 - transition band (vegetation + dirt + bare ground)
#   distance 16+   - town (untouched)
# Roads passing through the gradient also downgrade: secondary roads
# become dirt roads, sidewalks become bare ground.
const WILDERNESS_EDGE_PURE := 8
const WILDERNESS_EDGE_BAND := 16


func step_7_wilderness_gradient(grid: PackedByteArray) -> void:
	# Pass 1: downgrade roads/sidewalk/parking that pass through the band.
	# Pass 2: sample wilderness fill using PATCH-LEVEL clustering (not per-tile
	# RNG), so vegetation forms patches rather than checkerboard noise. The
	# patch hash bins tiles into 4x4 chunks that share a noise value, so
	# adjacent tiles in the same patch usually get the same wilderness sample.
	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			var d: int = min(min(x, y), min(MAP_TILES - 1 - x, MAP_TILES - 1 - y))
			if d >= WILDERNESS_EDGE_BAND:
				continue
			var current: int = grid[x + y * MAP_TILES]
			if current == TILE_MAIN_ROAD:
				continue
			if current == TILE_SECONDARY_ROAD:
				grid[x + y * MAP_TILES] = TILE_DIRT_ROAD
				continue
			if current == TILE_SIDEWALK or current == TILE_PARKING_LOT:
				grid[x + y * MAP_TILES] = TILE_BARE_GROUND
				current = TILE_BARE_GROUND
			grid[x + y * MAP_TILES] = _wilderness_sample(x, y, d, current)


func _patch_value(x: int, y: int) -> int:
	# Deterministic 0-99 patch hash, bucketed by 4-tile chunks so adjacent
	# tiles in the same chunk share the same value (clustered variation).
	var cx: int = x / 4
	var cy: int = y / 4
	var h: int = (cx * 73856093) ^ (cy * 19349663)
	return abs(h) % 100


func _wilderness_sample(x: int, y: int, distance_from_edge: int, current_tile: int) -> int:
	# Patch-clustered wilderness sampling. Probabilities tuned WAY down from
	# the previous per-tile RNG noise: pure wilderness is mostly dirt with
	# occasional vegetation patches; transition band is mostly current-tile
	# preservation with very rare vegetation worn-spots.
	var p: int = _patch_value(x, y)
	if distance_from_edge < WILDERNESS_EDGE_PURE:
		# Pure wilderness band - dirt-dominant with occasional patches.
		if p < 25:
			return TILE_VEGETATION
		if p < 30:
			return TILE_RUBBLE
		return TILE_DIRT_ROAD
	# Transition band (8..15) - mostly preserve current with rare patches.
	# Patch threshold scales with proximity to edge (closer = more patches).
	var veg_threshold: int = int(15.0 * (1.0 - float(distance_from_edge) / float(WILDERNESS_EDGE_BAND)))
	if p < veg_threshold:
		return TILE_VEGETATION
	return current_tile


# ---------------------------------------------------------------------
# Step 8 - variation
# ---------------------------------------------------------------------
# Real towns aren't perfectly uniform. Mark some lots as vacant (no
# building); mark some buildings as damaged (one corner rubbled);
# scatter a few small parks (2x2 to 4x4 vegetation patches) in
# transitional areas between zones.
func step_8_variation(lots: Array, buildings: Array, grid: PackedByteArray) -> void:
	# Vacant lots - clear the building footprint placeholder, leave the
	# lot's fill tile (yard / parking) visible. 4% of lots become vacant.
	for i in range(buildings.size()):
		if _rng.randf() < 0.04:
			var b: Dictionary = buildings[i]
			var lot: Dictionary = lots[i]
			var fill_tile := _lot_fill_tile_for_zone(lot["zone"])
			var rect: Rect2i = b.get("rect", Rect2i())
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				for y in range(rect.position.y, rect.position.y + rect.size.y):
					if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
						grid[x + y * MAP_TILES] = fill_tile
			b["vacant"] = true
	# Damaged buildings - 6% of remaining buildings get a corner rubbled.
	for i in range(buildings.size()):
		var b2: Dictionary = buildings[i]
		if b2.get("vacant", false):
			continue
		if _rng.randf() < 0.06:
			var rect2: Rect2i = b2.get("rect", Rect2i())
			# Damage one corner - 2x2 patch of rubble in a random corner.
			var corner_x: int = rect2.position.x if _rng.randf() < 0.5 else rect2.position.x + rect2.size.x - 2
			var corner_y: int = rect2.position.y if _rng.randf() < 0.5 else rect2.position.y + rect2.size.y - 2
			for dx in range(0, 2):
				for dy in range(0, 2):
					var px: int = corner_x + dx
					var py: int = corner_y + dy
					if px >= 0 and px < MAP_TILES and py >= 0 and py < MAP_TILES:
						# Already rubble (placeholder) - keep as rubble for damage
						# read. The intact part of the building still shows as
						# rubble placeholder; visual differentiation comes when
						# Lootables spawn (they will reflect the damaged flag).
						grid[px + py * MAP_TILES] = TILE_RUBBLE
			b2["damaged"] = true
	# Small parks - place 4 vegetation patches at fixed-but-not-on-lot
	# positions between zones (transitional areas).
	var park_positions := [
		Vector2i(80, 30),
		Vector2i(112, 30),
		Vector2i(80, 162),
		Vector2i(112, 162),
	]
	for pos in park_positions:
		var size_n: int = _rng.randi_range(2, 4)
		for dx in range(0, size_n):
			for dy in range(0, size_n):
				var x: int = pos.x + dx
				var y: int = pos.y + dy
				if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
					# Only paint if the tile is bare ground (don't overwrite
					# lots / roads / wilderness).
					var current: int = grid[x + y * MAP_TILES]
					if current == TILE_BARE_GROUND:
						grid[x + y * MAP_TILES] = TILE_VEGETATION


# ---------------------------------------------------------------------
# Step 9 - per-tile affordances
# ---------------------------------------------------------------------
# Five properties per tile, stored as 5 parallel PackedByteArrays in the
# returned Dictionary. Unit AI queries these to make tactical decisions
# (cover-seeking, chokepoint defense, route preference). Affordances are
# data only here; no AI consumes them yet.
#
# Watchlist failure mode: "80% of tiles in one category" / "every yard
# marked contained-area" / "every alley marked chokepoint". Self-validation
# below counts each category's tile share; if any single value exceeds
# 60% of relevant tiles we log a warning so the rules can be tightened.

# Coverage
const COV_OPEN := 0
const COV_PARTIAL := 1
const COV_FULL := 2
const COV_INTERIOR := 3
# Containment
const CTN_OPEN := 0
const CTN_PASSAGE := 1
const CTN_CHOKEPOINT := 2
const CTN_CONTAINED := 3
# Visibility
const VIS_EXPOSED := 0
const VIS_SHELTERED := 1
const VIS_HIDDEN := 2
# Connectivity (255 = N/A: tile isn't a path)
const CNN_NONE := 255
const CNN_THROUGH := 0
const CNN_JUNCTION := 1
const CNN_DEAD_END := 2
# Construction
const CST_BUILDABLE := 0
const CST_SURFACE_ONLY := 1
const CST_BLOCKED := 2
const CST_RESTRICTED := 3


func step_9_affordances(grid: PackedByteArray, _buildings: Array) -> Dictionary:
	var size: int = MAP_TILES * MAP_TILES
	var coverage := PackedByteArray()
	var containment := PackedByteArray()
	var visibility := PackedByteArray()
	var connectivity := PackedByteArray()
	var construction := PackedByteArray()
	coverage.resize(size)
	containment.resize(size)
	visibility.resize(size)
	connectivity.resize(size)
	construction.resize(size)

	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			var idx: int = x + y * MAP_TILES
			var tile: int = grid[idx]
			# Construction.
			construction[idx] = _construction_for_tile(tile)
			# Coverage: interior if rubble placeholder (building footprint),
			# full at 1 tile from building, partial at 2-3 tiles, open beyond.
			# Extended from radius 2 to 3 to align with the spec's "near
			# walls = cover" intent and bring the OPEN distribution under
			# 60% on a town this size.
			var cov := COV_OPEN
			if tile == TILE_RUBBLE and _is_building_placeholder(x, y, grid):
				cov = COV_INTERIOR
			else:
				var nearest_b: int = _distance_to_building(x, y, grid, 3)
				if nearest_b == 1:
					cov = COV_FULL
				elif nearest_b == 2 or nearest_b == 3:
					cov = COV_PARTIAL
			coverage[idx] = cov
			# Visibility derived from coverage + tile context.
			visibility[idx] = _visibility_from(cov, tile)
			# Containment.
			containment[idx] = _containment_for_tile(x, y, tile, grid)
			# Connectivity: only set if tile is a path-type.
			if _is_path_tile(tile):
				connectivity[idx] = _connectivity_for(x, y, grid)
			else:
				connectivity[idx] = CNN_NONE

	# Self-validate distribution.
	_validate_affordance_distribution("coverage", coverage, size)
	_validate_affordance_distribution("containment", containment, size)
	_validate_affordance_distribution("visibility", visibility, size)
	# Connectivity skipped - most tiles are CNN_NONE which is expected.
	_validate_affordance_distribution("construction", construction, size)

	return {
		"coverage": coverage,
		"containment": containment,
		"visibility": visibility,
		"connectivity": connectivity,
		"construction": construction,
	}


func _construction_for_tile(tile: int) -> int:
	match tile:
		TILE_MAIN_ROAD, TILE_SECONDARY_ROAD, TILE_SIDE_STREET, TILE_DIRT_ROAD, TILE_SIDEWALK, TILE_PARKING_LOT:
			return CST_SURFACE_ONLY
		TILE_YARD, TILE_BARE_GROUND, TILE_VEGETATION:
			return CST_BUILDABLE
		TILE_RUBBLE:
			# Rubble placeholders inside building footprints are blocked;
			# rubble in wilderness is buildable. Distinguish by neighborhood.
			return CST_BLOCKED  # conservative; phase 4 doesn't differentiate
	return CST_BUILDABLE


func _is_path_tile(tile: int) -> bool:
	return tile == TILE_MAIN_ROAD or tile == TILE_SECONDARY_ROAD or tile == TILE_SIDE_STREET or tile == TILE_DIRT_ROAD or tile == TILE_SIDEWALK


func _is_building_placeholder(x: int, y: int, grid: PackedByteArray) -> bool:
	# Building footprints are 3x3 or larger blocks of TILE_RUBBLE produced
	# by step 5. A rubble tile with rubble neighbors in 4-connectivity is
	# almost certainly a building footprint (not edge-band rubble).
	var n := 0
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or nx >= MAP_TILES or ny < 0 or ny >= MAP_TILES:
			continue
		if grid[nx + ny * MAP_TILES] == TILE_RUBBLE:
			n += 1
	return n >= 2


func _distance_to_building(x: int, y: int, grid: PackedByteArray, max_d: int) -> int:
	# Manhattan distance to the nearest building placeholder tile, capped
	# at max_d. Returns max_d + 1 if no building within range.
	for d in range(1, max_d + 1):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				if abs(dx) + abs(dy) != d:
					continue
				var nx: int = x + dx
				var ny: int = y + dy
				if nx < 0 or nx >= MAP_TILES or ny < 0 or ny >= MAP_TILES:
					continue
				var tile: int = grid[nx + ny * MAP_TILES]
				if tile == TILE_RUBBLE and _is_building_placeholder(nx, ny, grid):
					return d
	return max_d + 1


func _visibility_from(cov: int, tile: int) -> int:
	if cov == COV_INTERIOR:
		return VIS_HIDDEN
	if cov == COV_FULL or cov == COV_PARTIAL:
		return VIS_SHELTERED
	if tile == TILE_DIRT_ROAD and _is_path_tile(tile):  # alley
		return VIS_SHELTERED
	if tile == TILE_VEGETATION:
		return VIS_SHELTERED  # vegetation cover
	return VIS_EXPOSED


func _containment_for_tile(x: int, y: int, tile: int, grid: PackedByteArray) -> int:
	# Building interiors are not "contained-area" in the spec sense - that's
	# for outdoor enclosed spaces (yards surrounded by buildings).
	if tile == TILE_RUBBLE and _is_building_placeholder(x, y, grid):
		return CTN_OPEN  # interior, doesn't apply
	# Alleys = passage.
	if tile == TILE_DIRT_ROAD and _is_path_tile(tile):
		return CTN_PASSAGE
	# Containment requires building walls on 3+ sides in a small radius.
	if tile == TILE_YARD or tile == TILE_PARKING_LOT:
		var walls_around := 0
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			# Look 2 tiles out for a building wall.
			for step in range(1, 3):
				var nx: int = x + d.x * step
				var ny: int = y + d.y * step
				if nx < 0 or nx >= MAP_TILES or ny < 0 or ny >= MAP_TILES:
					break
				var nt: int = grid[nx + ny * MAP_TILES]
				if nt == TILE_RUBBLE and _is_building_placeholder(nx, ny, grid):
					walls_around += 1
					break
		if walls_around >= 3:
			return CTN_CONTAINED
	return CTN_OPEN


func _connectivity_for(x: int, y: int, grid: PackedByteArray) -> int:
	# Count road neighbors in 4-connectivity.
	var path_neighbors := 0
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or nx >= MAP_TILES or ny < 0 or ny >= MAP_TILES:
			continue
		if _is_path_tile(grid[nx + ny * MAP_TILES]):
			path_neighbors += 1
	if path_neighbors >= 3:
		return CNN_JUNCTION
	if path_neighbors <= 1:
		return CNN_DEAD_END
	return CNN_THROUGH


func _validate_affordance_distribution(name: String, arr: PackedByteArray, total: int) -> void:
	# Count each unique value; warn if any single value covers > 60% of tiles.
	var counts: Dictionary = {}
	for v in arr:
		counts[v] = counts.get(v, 0) + 1
	for k in counts.keys():
		var frac: float = float(counts[k]) / float(total)
		if frac > 0.60:
			print("[TownPlanner] WARN: %s value %d covers %.1f%% of tiles - rules may be too loose" % [name, k, frac * 100.0])


# ---------------------------------------------------------------------
# Step 10 - spawn clear zones
# ---------------------------------------------------------------------
# Around each spawn anchor, clear a 16x16 zone of lots/buildings and set
# tiles to yard. HQ goes at the center of each cleared zone at match start.
const SPAWN_CLEAR_RADIUS := 8  # 16x16 zone = 8 tiles each direction from anchor


func step_10_spawn_clear_zones(lots: Array, buildings: Array, grid: PackedByteArray) -> Array:
	var zones: Array = []
	var spawn_anchors := [
		ANCHOR_SPAWN_NW, ANCHOR_SPAWN_NE, ANCHOR_SPAWN_SE, ANCHOR_SPAWN_SW,
	]
	for anchor in spawn_anchors:
		var rect := Rect2i(
			anchor.x - SPAWN_CLEAR_RADIUS,
			anchor.y - SPAWN_CLEAR_RADIUS,
			SPAWN_CLEAR_RADIUS * 2,
			SPAWN_CLEAR_RADIUS * 2,
		)
		zones.append({"anchor": anchor, "rect": rect})
		# Mark intersecting lots / buildings as removed.
		for i in range(lots.size()):
			var lot: Dictionary = lots[i]
			var lr: Rect2i = lot["rect"]
			if _rects_intersect(lr, rect):
				lot["spawn_cleared"] = true
				if i < buildings.size():
					buildings[i]["spawn_cleared"] = true
		# Paint clear zone tiles as yard.
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if x < 0 or x >= MAP_TILES or y < 0 or y >= MAP_TILES:
					continue
				grid[x + y * MAP_TILES] = TILE_YARD
		# Place a U-cluster of 4 small residential lots around the spawn,
		# opening toward map center so Survivor (and any fortifying faction)
		# has wall-able terrain at start.
		_add_spawn_cluster(anchor, lots, buildings, grid)
	return zones


# Settlement-ready cluster: 4 small (3x3) residential houses on 5x5 lots
# arranged in an L around the spawn corner, opening toward map center.
# Houses face the spawn anchor so doors are visible from the HQ.
const CLUSTER_HOUSE_SIZE := 3
const CLUSTER_LOT_SIZE := 5
const CLUSTER_DIST_FROM_ANCHOR := 11  # arm offset perpendicular to opening


func _add_spawn_cluster(anchor: Vector2i, lots: Array, buildings: Array, grid: PackedByteArray) -> void:
	# Direction from anchor toward map center - houses go on the opposite
	# side so the U opens center-ward.
	var center := Vector2i(MAP_TILES / 2, MAP_TILES / 2)
	var to_center: Vector2i = center - anchor
	# Cardinal directions: 1 = center-side, -1 = wilderness-side.
	var x_dir: int = 1 if to_center.x > 0 else -1
	var y_dir: int = 1 if to_center.y > 0 else -1
	# Arm-1 sits perpendicular to y-axis at offset -y_dir * CLUSTER_DIST.
	var arm1_y: int = anchor.y + (-y_dir) * CLUSTER_DIST_FROM_ANCHOR
	# Arm-1 houses face anchor (direction = +y_dir along y).
	var arm1_facing := Vector2i(0, y_dir)
	# 2 houses on arm-1, 7 tiles apart along x.
	for offset in [-4, 4]:
		var px: int = anchor.x + offset
		_add_cluster_house(Vector2i(px, arm1_y), arm1_facing, lots, buildings, grid)
	# Arm-2 sits perpendicular to x-axis at offset -x_dir * CLUSTER_DIST.
	var arm2_x: int = anchor.x + (-x_dir) * CLUSTER_DIST_FROM_ANCHOR
	var arm2_facing := Vector2i(x_dir, 0)
	for offset2 in [-4, 4]:
		var py: int = anchor.y + offset2
		_add_cluster_house(Vector2i(arm2_x, py), arm2_facing, lots, buildings, grid)


func _add_cluster_house(center_tile: Vector2i, facing: Vector2i, lots: Array, buildings: Array, grid: PackedByteArray) -> void:
	# Center the 5x5 lot and 3x3 building on center_tile.
	var lot_top_left := Vector2i(
		center_tile.x - CLUSTER_LOT_SIZE / 2,
		center_tile.y - CLUSTER_LOT_SIZE / 2,
	)
	var building_top_left := Vector2i(
		center_tile.x - CLUSTER_HOUSE_SIZE / 2,
		center_tile.y - CLUSTER_HOUSE_SIZE / 2,
	)
	# Bounds check.
	if lot_top_left.x < 0 or lot_top_left.y < 0:
		return
	if lot_top_left.x + CLUSTER_LOT_SIZE > MAP_TILES:
		return
	if lot_top_left.y + CLUSTER_LOT_SIZE > MAP_TILES:
		return
	var lot_rect := Rect2i(lot_top_left.x, lot_top_left.y, CLUSTER_LOT_SIZE, CLUSTER_LOT_SIZE)
	var building_rect := Rect2i(building_top_left.x, building_top_left.y, CLUSTER_HOUSE_SIZE, CLUSTER_HOUSE_SIZE)
	lots.append({
		"rect": lot_rect,
		"frontage_dir": facing,
		"zone": ZONE_RESIDENTIAL_NW,
		"spawn_cluster": true,
	})
	buildings.append({
		"rect": building_rect,
		"facing": facing,
		"zone": ZONE_RESIDENTIAL_NW,
		"spawn_cluster": true,
	})
	# Paint lot + building tiles.
	for x in range(lot_top_left.x, lot_top_left.x + CLUSTER_LOT_SIZE):
		for y in range(lot_top_left.y, lot_top_left.y + CLUSTER_LOT_SIZE):
			if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
				grid[x + y * MAP_TILES] = TILE_YARD
	for x in range(building_top_left.x, building_top_left.x + CLUSTER_HOUSE_SIZE):
		for y in range(building_top_left.y, building_top_left.y + CLUSTER_HOUSE_SIZE):
			if x >= 0 and x < MAP_TILES and y >= 0 and y < MAP_TILES:
				grid[x + y * MAP_TILES] = TILE_RUBBLE


func _rects_intersect(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.position.x + b.size.x and \
		a.position.x + a.size.x > b.position.x and \
		a.position.y < b.position.y + b.size.y and \
		a.position.y + a.size.y > b.position.y


# ---------------------------------------------------------------------
# Step 11 - lootable markers
# ---------------------------------------------------------------------
# Convert building data into Lootable spawn entries that Main consumes.
# Zone -> Lootable.neighborhood_type. Spawn position = building rect
# center in world pixels.
func step_11_lootable_markers(buildings: Array) -> Array:
	var lootables: Array = []
	for b in buildings:
		if b.get("vacant", false):
			continue
		if b.get("spawn_cleared", false):
			continue
		var zone: String = b["zone"]
		var lootable_type: String = _lootable_type_for_zone(zone)
		var rect: Rect2i = b["rect"]
		var center_px := Vector2(
			(float(rect.position.x) + float(rect.size.x) * 0.5) * IsoView.TILE_WORLD_PX,
			(float(rect.position.y) + float(rect.size.y) * 0.5) * IsoView.TILE_WORLD_PX,
		)
		lootables.append({ "pos": center_px, "type": lootable_type })
	# Rural farmhouses in the wilderness band - 6 scattered positions.
	var rural_positions := [
		Vector2i(10, 96), Vector2i(180, 96), Vector2i(96, 10), Vector2i(96, 180),
		Vector2i(12, 60), Vector2i(180, 130),
	]
	for rp in rural_positions:
		var center_px2 := Vector2(
			float(rp.x) * IsoView.TILE_WORLD_PX,
			float(rp.y) * IsoView.TILE_WORLD_PX,
		)
		lootables.append({ "pos": center_px2, "type": "residential" })
	return lootables


func _lootable_type_for_zone(zone: String) -> String:
	match zone:
		ZONE_DOWNTOWN:
			# Mix of commercial and civic - alternate by index would be cleaner
			# but for now everything in downtown is commercial.
			return "commercial"
		ZONE_INDUSTRIAL:
			return "industrial"
		ZONE_MEDICAL:
			# Some are medical, some security
			return "medical"
	return "residential"


# ---------------------------------------------------------------------
# Step 12 - validation
# ---------------------------------------------------------------------
# Sanity check the final data. Print warnings; nothing is rejected.
func step_12_validate(data: Dictionary) -> Array:
	var warnings: Array = []
	var lots_count: int = (data["lots"] as Array).size()
	var buildings_count: int = (data["buildings"] as Array).size()
	var lootables_count: int = (data["lootables"] as Array).size()
	print("[TownPlanner] %d lots, %d buildings, %d lootables, %d alleys, %d spawn zones" % [
		lots_count,
		buildings_count,
		lootables_count,
		(data["alleys"] as Array).size(),
		(data["spawn_zones"] as Array).size(),
	])
	if buildings_count > lots_count:
		warnings.append("buildings exceed lots (should be 1:1)")
		print("[TownPlanner] WARN: buildings (%d) > lots (%d)" % [buildings_count, lots_count])
	if lootables_count == 0:
		warnings.append("no lootables - step 11 failed")
		print("[TownPlanner] WARN: no lootables generated")
	return warnings
