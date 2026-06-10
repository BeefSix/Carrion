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
const TILE_H := 32  # 2:1 dimetric. Was 48 (4:3 oblique) pre-2026-06-09.
const MAP_TILES := 192

# Tile PNG sources (Pixellab tiles_pro 64px isometric top-down) — slot index
# matches TownPlanner's TILE_* constants. Filenames are relative to TILE_DIR.
# If a PNG is missing or fails to load, the corresponding TILE_COLORS entry
# below is used as a flat-color fallback (defensive at the asset boundary).
const TILE_DIR := "res://assets/tiles/ground/"
const TILE_FILES := [
	"tile_0.png",   # 0 main road
	"tile_1.png",   # 1 sidewalk
	"tile_11.png",  # 2 secondary road
	"tile_2.png",   # 3 side street
	"tile_4.png",   # 4 parking lot
	"tile_14.png",  # 5 yard
	"tile_6.png",   # 6 bare ground
	"tile_7.png",   # 7 dirt road
	"tile_8.png",   # 8 vegetation
	"tile_15.png",  # 9 rubble
	"tile_10.png",  # 10 fence
]

# Fallback flat colors — used when the matching PNG can't be loaded so the
# tilemap still renders something. Indices must match TownPlanner's TILE_*.
const TILE_COLORS := [
	Color("2a2a2a"),  # 0 main road
	Color("5a5a5a"),  # 1 sidewalk
	Color("3a3a3a"),  # 2 secondary road
	Color("2f2820"),  # 3 side street
	Color("404040"),  # 4 parking lot
	Color("444a36"),  # 5 yard
	Color("46413a"),  # 6 bare ground
	Color("45382e"),  # 7 dirt road
	Color("3c4032"),  # 8 vegetation
	Color("2a2520"),  # 9 rubble
	Color("3c402e"),  # 10 fence
]

# ---- Palette unification (2026-06-11, "skin the maps" pass) ----
# The 11 source tiles were generated separately and never agreed on a
# palette: cool near-black roads next to bright warm-brown yards read as
# a quilt, not ground. Fix at LOAD TIME: each tile's pixels are remapped
# by luminance onto a per-terrain color ramp from one bleak family —
# hue carries terrain identity (asphalt cool, organics khaki/olive,
# dirt warm brown), the source tile's texture survives as value
# variation. Source PNGs untouched; the ramps are the tuning surface.
# RENDER-ONLY.
const TILE_RAMPS := [
	[Color("1d1d20"), Color("36363c")],  # 0 main road — cool asphalt
	[Color("35332e"), Color("565349")],  # 1 sidewalk — warm concrete
	[Color("222226"), Color("3b3b41")],  # 2 secondary road
	[Color("272420"), Color("423e35")],  # 3 side street — worn mix
	[Color("2a2a2d"), Color("45454a")],  # 4 parking lot
	[Color("46422e"), Color("6e684a")],  # 5 yard — dead-grass khaki
	[Color("41382c"), Color("5f5343")],  # 6 bare ground — dirt
	[Color("3a3228"), Color("584a3b")],  # 7 dirt road
	[Color("363d2a"), Color("535e3d")],  # 8 vegetation — olive
	[Color("2c2823"), Color("494339")],  # 9 rubble
	[Color("373226"), Color("514a39")],  # 10 fence
]
# Posterize the ramp position into discrete steps — keeps the pixel-art
# read instead of a smooth gradient wash.
const RAMP_STEPS := 6

# Per-cell variation: each atlas tile gets alternates (h-flip + small
# value nudges) picked by a deterministic hash of the cell coords, so a
# 30-cell road doesn't wallpaper one stamp. RENDER-ONLY: gameplay reads
# atlas coords (get_tile_type_at), which alternates never change.
const ALT_MODULATES := [Color(1, 1, 1), Color(0.94, 0.94, 0.94), Color(1.05, 1.05, 1.05), Color(0.97, 0.97, 0.97)]
const ALT_FLIPS := [false, true, false, true]


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
	# Alternate choice is a deterministic coordinate hash (same picture on
	# every client/run) — pure anti-wallpaper variation.
	for x in range(MAP_TILES):
		for y in range(MAP_TILES):
			var t: int = grid[x + y * MAP_TILES]
			var h: int = ((x * 73856093) ^ (y * 19349663)) & 0x7FFFFFFF
			set_cell(Vector2i(x, y), 0, Vector2i(t, 0), h % ALT_MODULATES.size())


func _build_tileset() -> void:
	# Diamond-masked atlas. TILE_W x TILE_H per tile, transparent outside the
	# diamond so adjacent iso tiles tile cleanly without overlap. Each slot
	# loads its PNG (Pixellab tiles_pro output, 64x64) and is scaled to
	# TILE_W x TILE_H. The diamond mask is still applied so source artwork
	# outside the iso shape (corners of the PNG) doesn't bleed into neighbors.
	# Missing or invalid PNGs fall back to TILE_COLORS[i] flat color.
	var count: int = TILE_COLORS.size()
	var img := Image.create(TILE_W * count, TILE_H, false, Image.FORMAT_RGBA8)
	var cx: float = TILE_W * 0.5
	var cy: float = TILE_H * 0.5
	for i in range(count):
		var x_offset: int = i * TILE_W
		var src_img: Image = _load_tile_image(i)
		# Pre-scan: the source tile's luminance range inside the diamond,
		# so the ramp remap can stretch whatever texture the tile has
		# (even near-flat ones) across the full terrain ramp.
		var lum_min: float = 1.0
		var lum_max: float = 0.0
		if src_img != null:
			for px in range(TILE_W):
				for py in range(TILE_H):
					if abs(float(px) + 0.5 - cx) / cx + abs(float(py) + 0.5 - cy) / cy <= 1.0:
						var c: Color = src_img.get_pixel(px, py)
						if c.a >= 0.01:
							var l: float = c.get_luminance()
							lum_min = minf(lum_min, l)
							lum_max = maxf(lum_max, l)
		var lum_span: float = maxf(lum_max - lum_min, 0.0001)
		for px in range(TILE_W):
			for py in range(TILE_H):
				var dx: float = abs(float(px) + 0.5 - cx) / cx
				var dy: float = abs(float(py) + 0.5 - cy) / cy
				if dx + dy <= 1.0:
					var pixel: Color
					if src_img != null:
						pixel = src_img.get_pixel(px, py)
						if pixel.a < 0.01:
							pixel = TILE_RAMPS[i][0].lerp(TILE_RAMPS[i][1], 0.5)
						else:
							# Luminance -> posterized ramp position -> terrain color.
							var t: float = clampf((pixel.get_luminance() - lum_min) / lum_span, 0.0, 1.0)
							t = floorf(t * float(RAMP_STEPS - 1) + 0.5) / float(RAMP_STEPS - 1)
							pixel = TILE_RAMPS[i][0].lerp(TILE_RAMPS[i][1], t)
					else:
						pixel = TILE_RAMPS[i][0].lerp(TILE_RAMPS[i][1], 0.5)
					img.set_pixel(x_offset + px, py, pixel)
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
		# Alternates 1..N-1 (0 is the base tile): h-flips + value nudges
		# for per-cell variation. Iso diamonds mirror cleanly.
		for a in range(1, ALT_MODULATES.size()):
			var alt_id: int = src.create_alternative_tile(Vector2i(i, 0))
			var td: TileData = src.get_tile_data(Vector2i(i, 0), alt_id)
			td.flip_h = ALT_FLIPS[a]
			td.modulate = ALT_MODULATES[a]
	ts.add_source(src, 0)
	tile_set = ts


func _load_tile_image(slot: int) -> Image:
	# Load a tile PNG and resize to TILE_W x TILE_H. Returns null if the
	# file is missing or load fails so the caller can fall back to flat color.
	if slot < 0 or slot >= TILE_FILES.size():
		return null
	var path: String = TILE_DIR + TILE_FILES[slot]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var src_img: Image = tex.get_image()
	if src_img == null:
		return null
	if src_img.is_compressed():
		src_img.decompress()
	if src_img.get_format() != Image.FORMAT_RGBA8:
		src_img.convert(Image.FORMAT_RGBA8)
	if src_img.get_width() != TILE_W or src_img.get_height() != TILE_H:
		src_img.resize(TILE_W, TILE_H, Image.INTERPOLATE_BILINEAR)
	return src_img
