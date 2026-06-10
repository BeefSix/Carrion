extends RefCounted

# Authored map recipes (MAP_DESIGN.md, Matt directive 2026-06-10).
# Each recipe deterministically builds the same town-data contract Main
# consumes from TownPlanner: tile_grid (192x192 PackedByteArray),
# lootables [{pos, type, infested}], plus the NEW scenery list
# [{pos, type}] (Regular buildings — collision + occlusion, no use).
#
# Determinism: one fixed-seed local RNG per build (the map is part of the
# match's identical starting state — same layout every match, every
# client; the match seed plays no part here). No physics, no transcend-
# entals, pure array painting.
#
# Tile ids (GroundTiles.TILE_FILES order):
#   0 main road, 1 sidewalk, 2 secondary road, 3 side street,
#   4 parking lot, 5 yard, 6 bare ground, 7 dirt road, 8 vegetation,
#   9 rubble, 10 fence.

const GRID := 192
const TILE := 32.0
const RECIPE_SEED := 777  # fixed: maps are authored artifacts, not rolls

# Spawn quarters (match Main.SPAWN_NW / SPAWN_SE): keep these clear.
const SPAWN_TILES := [Vector2i(24, 24), Vector2i(160, 160)]
const SPAWN_CLEAR_RADIUS := 14  # tiles around each spawn kept building-free


static func available() -> Array:
	return ["downtown", "terrace", "orchard"]


static func build(map_name: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = RECIPE_SEED
	var grid := PackedByteArray()
	grid.resize(GRID * GRID)
	var out := {"tile_grid": grid, "lootables": [], "scenery": [], "props": [], "decals": []}
	match map_name:
		"downtown":
			_build_downtown(out, rng)
		"terrace":
			_build_terrace(out, rng)
		"orchard":
			_build_orchard(out, rng)
		_:
			return {}
	_scatter_props(out, rng, map_name)
	_scatter_decals(out, rng, map_name)
	return out


# Prop scatter (2026-06-10): render-only doodads keyed to the tile they
# stand on, rolled from the same fixed-seed rng AFTER layout so the grid
# is readable. {tile_id: [[chance, [kinds...]], ...]} per map. Kinds map
# to textures in Main.PROP_TEXTURES. Spawn clear radius respected.
const PROP_TABLES := {
	"downtown": {
		0: [[0.022, ["car"]]],                                 # main road: wrecks
		2: [[0.018, ["car"]]],                                 # avenue
		1: [[0.018, ["lamp", "hydrant", "mailbox", "cone"]]],  # sidewalk furniture
		4: [[0.036, ["bench", "cart", "dumpster", "barrel"]]], # plazas
		9: [[0.054, ["brickpile", "pallet"]]],                 # rubble lots
	},
	"terrace": {
		3: [[0.014, ["car"]]],                                 # lanes: parked wrecks
		2: [[0.018, ["car", "cone"]]],
		1: [[0.014, ["lamp", "mailbox", "hydrant"]]],
		5: [[0.011, ["tree", "pallet"]]],                      # yards
		8: [[0.036, ["bench", "tree"]]],                       # the park
		9: [[0.054, ["brickpile", "dumpster"]]],
	},
	"orchard": {
		8: [[0.009, ["tree"]]],                                # fields: dead orchard
		5: [[0.014, ["tree", "barrel"]]],
		7: [[0.014, ["car", "pallet"]]],                       # dirt drives
		2: [[0.014, ["car"]]],
		9: [[0.045, ["brickpile", "barrel"]]],
	},
}


# Ground wear decals (TerrainKit Phase 3): stains/cracks/litter/blood at
# reference-image density. Same deterministic post-layout roll as props.
const DECAL_TABLES := {
	"downtown": {
		0: [[0.036, ["oil", "cracks"]], [0.008, ["blood"]]],
		2: [[0.032, ["oil", "cracks"]], [0.006, ["blood"]]],
		3: [[0.027, ["cracks", "oil"]]],
		1: [[0.054, ["cracks", "litter"]]],
		4: [[0.060, ["litter", "oil"]], [0.006, ["blood"]]],
	},
	"terrace": {
		2: [[0.027, ["cracks", "oil"]]],
		3: [[0.022, ["cracks"]]],
		1: [[0.045, ["cracks", "litter"]]],
		5: [[0.014, ["litter"]]],
	},
	"orchard": {
		2: [[0.022, ["cracks"]]],
		7: [[0.022, ["litter"]]],
		6: [[0.014, ["litter"]]],
	},
}


static func _scatter_decals(out: Dictionary, rng: RandomNumberGenerator, map_name: String) -> void:
	var table: Dictionary = DECAL_TABLES.get(map_name, {})
	if table.is_empty():
		return
	var g: PackedByteArray = out["tile_grid"]
	for ty in range(2, GRID - 2):
		for tx in range(2, GRID - 2):
			var rules = table.get(g[ty * GRID + tx])
			if rules == null:
				continue
			for rule in rules:
				if rng.randf() < rule[0]:
					var kinds: Array = rule[1]
					var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
					var jitter := Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
					out["decals"].append({"pos": _world(tx, ty) + jitter, "kind": kind})
					break


static func _scatter_props(out: Dictionary, rng: RandomNumberGenerator, map_name: String) -> void:
	var table: Dictionary = PROP_TABLES.get(map_name, {})
	if table.is_empty():
		return
	var g: PackedByteArray = out["tile_grid"]
	for ty in range(2, GRID - 2):
		for tx in range(2, GRID - 2):
			var rules = table.get(g[ty * GRID + tx])
			if rules == null or _near_spawn(tx, ty):
				continue
			for rule in rules:
				if rng.randf() < rule[0]:
					var kinds: Array = rule[1]
					var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
					var jitter := Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0))
					out["props"].append({"pos": _world(tx, ty) + jitter, "kind": kind})
					break


# ---------------------------------------------------------------- helpers

static func _fill(g: PackedByteArray, tile: int) -> void:
	for i in range(g.size()):
		g[i] = tile


static func _rect(g: PackedByteArray, x0: int, y0: int, w: int, h: int, tile: int) -> void:
	for y in range(maxi(y0, 0), mini(y0 + h, GRID)):
		for x in range(maxi(x0, 0), mini(x0 + w, GRID)):
			g[y * GRID + x] = tile


static func _hroad(g: PackedByteArray, y: int, width: int, tile: int) -> void:
	_rect(g, 0, y, GRID, width, tile)
	# Sidewalk fringe for proper roads.
	if tile == 0 or tile == 2:
		_rect(g, 0, y - 1, GRID, 1, 1)
		_rect(g, 0, y + width, GRID, 1, 1)


static func _vroad(g: PackedByteArray, x: int, width: int, tile: int) -> void:
	_rect(g, x, 0, width, GRID, tile)
	if tile == 0 or tile == 2:
		_rect(g, x - 1, 0, 1, GRID, 1)
		_rect(g, x + width, 0, 1, GRID, 1)


static func _world(tx: float, ty: float) -> Vector2:
	return Vector2(tx * TILE + TILE * 0.5, ty * TILE + TILE * 0.5)


static func _near_spawn(tx: int, ty: int) -> bool:
	for s in SPAWN_TILES:
		if absi(tx - s.x) <= SPAWN_CLEAR_RADIUS and absi(ty - s.y) <= SPAWN_CLEAR_RADIUS:
			return true
	return false


static func _center_band(tx: int, ty: int) -> int:
	# 0 = fringe, 1 = mid, 2 = center — drives the R/L/I mix ladder
	# (the SC expansion ladder: safe -> contested -> rich-and-bitten).
	var d: float = Vector2(tx - GRID / 2.0, ty - GRID / 2.0).length()
	if d < 36.0:
		return 2
	if d < 72.0:
		return 1
	return 0


# Mix tables per band: [regular, lootable, infested] cumulative weights.
static func _place(out: Dictionary, rng: RandomNumberGenerator, tx: int, ty: int,
		btype: String, mix_by_band: Array) -> void:
	if _near_spawn(tx, ty):
		return
	var band: int = _center_band(tx, ty)
	var mix: Array = mix_by_band[band]  # e.g. [0.70, 0.95] = 70% R, 25% L, 5% I
	var roll: float = rng.randf()
	var pos: Vector2 = _world(tx, ty)
	if roll < float(mix[0]):
		out["scenery"].append({"pos": pos, "type": btype})
	elif roll < float(mix[1]):
		out["lootables"].append({"pos": pos, "type": btype, "infested": false})
	else:
		out["lootables"].append({"pos": pos, "type": btype, "infested": true})


# ---------------------------------------------------------- MAP 1: DOWNTOWN
# Canyon warfare: Manhattan grid, regular-building block walls, two plaza
# basins, wide central avenues. Longest rush distance (anti-rush map).

static func _build_downtown(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g: PackedByteArray = out["tile_grid"]
	_fill(g, 6)  # bare urban ground
	# Street grid: side streets every 16 tiles, central avenues at 94-97.
	for x in range(16, GRID, 16):
		_vroad(g, x, 2, 3)
	for y in range(16, GRID, 16):
		_hroad(g, y, 2, 3)
	_vroad(g, 94, 4, 0)   # central avenue cross
	_hroad(g, 94, 4, 0)
	# Plazas (zombie basins) — open parking aprons off-center.
	_rect(g, 56, 116, 14, 14, 4)
	_rect(g, 122, 62, 14, 14, 4)
	# Blocks: building ring inside each 16-tile block (3-tile footprints).
	var mix := [[0.060, 0.95], [0.60, 0.85], [0.40, 0.70]]  # fringe/mid/center
	for by in range(0, GRID, 16):
		for bx in range(0, GRID, 16):
			# Skip blocks swallowed by plazas/avenues.
			if (bx >= 88 and bx < 104) or (by >= 88 and by < 104):
				continue
			for slot in [[3, 3], [9, 3], [3, 9], [9, 9]]:
				var tx: int = bx + slot[0]
				var ty: int = by + slot[1]
				if tx + 3 >= GRID or ty + 3 >= GRID:
					continue
				var t: int = g[ty * GRID + tx]
				if t == 0 or t == 1 or t == 2 or t == 3 or t == 4:
					continue  # don't build on streets/plazas
				var btype: String = "commercial" if _center_band(tx, ty) >= 1 else "residential"
				if rng.randf() < 0.18:
					btype = "industrial"
				_place(out, rng, tx, ty, btype, mix)


# -------------------------------------------------------- MAP 2: TERRACE ROW
# Trench lines: contiguous row-home walls, gap chokes, lane warfare.

static func _build_terrace(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g: PackedByteArray = out["tile_grid"]
	_fill(g, 5)  # yards everywhere between rows
	# Lane streets every 10 tiles (east-west).
	for y in range(10, GRID, 10):
		_hroad(g, y, 2, 3)
	# Two arterial crossings + the center park basin.
	_vroad(g, 48, 3, 2)
	_vroad(g, 140, 3, 2)
	_rect(g, 86, 86, 20, 20, 8)  # central park (vegetation basin)
	var mix := [[0.060, 0.95], [0.50, 0.80], [0.35, 0.70]]
	# Rows: contiguous 2-tile houses between lanes, with gap chokes.
	for ry in range(4, GRID - 4, 10):
		var gap_phase: int = rng.randi_range(0, 6)
		var tx: int = 2
		var house_i: int = 0
		while tx < GRID - 4:
			# Skip streets, park, arterials.
			var t: int = g[ry * GRID + tx]
			if t == 2 or t == 3 or t == 1 or t == 8:
				tx += 2
				continue
			# Gap choke: every ~12 houses leave a 2-house burned lot.
			if (house_i + gap_phase) % 12 >= 10:
				_rect(g, tx, ry, 2, 2, 9)  # rubble lot
				tx += 2
				house_i += 1
				continue
			_place(out, rng, tx, ry, "residential", mix)
			tx += 2
			house_i += 1
	# Center cluster: school + strip mall around the park.
	for c in [[80, 90, "civic"], [108, 90, "commercial"], [90, 80, "commercial"], [90, 108, "civic"]]:
		out["lootables"].append({"pos": _world(c[0], c[1]), "type": c[2], "infested": rng.randf() < 0.4})


# ------------------------------------------------------ MAP 3: ORCHARD SPRAWL
# Open skirmish country: detached homes, driveways, big basins, short rush.

static func _build_orchard(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g: PackedByteArray = out["tile_grid"]
	_fill(g, 5)  # grass
	# Loose street net: fewer roads, bigger cells.
	for x in range(24, GRID, 28):
		_vroad(g, x, 2, 3)
	for y in range(24, GRID, 28):
		_hroad(g, y, 2, 3)
	_vroad(g, 94, 3, 2)  # the cross arterials
	_hroad(g, 94, 3, 2)
	# Open fields (zombie basins).
	for f in [[30, 120, 22, 18], [130, 36, 20, 22], [60, 60, 14, 12]]:
		_rect(g, f[0], f[1], f[2], f[3], 8)
	var mix := [[0.060, 0.95], [0.55, 0.85], [0.30, 0.70]]
	# Single homes along streets: one per ~7 tiles, with driveway stubs.
	for y in range(24, GRID, 28):
		for x in range(4, GRID - 4, 7):
			var ty: int = y + 3  # one lot south of the street
			if ty + 2 >= GRID or _near_spawn(x, ty):
				continue
			var t: int = g[ty * GRID + x]
			if t != 5:
				continue
			# Driveway stub from street to lot.
			_rect(g, x, y + 2, 1, 2, 7)
			_place(out, rng, x, ty, "residential", mix)
	# Center cluster: gas station + market at the cross.
	for c in [[88, 100, "industrial"], [100, 88, "commercial"], [100, 100, "commercial"]]:
		out["lootables"].append({"pos": _world(c[0], c[1]), "type": c[2], "infested": rng.randf() < 0.45})
