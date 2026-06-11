extends RefCounted

# Prefab building compositor (2026-06-11, the PZ/CDDA model): buildings
# are DATA — ordered layer lists of modular HD kit pieces baked into one
# texture at load, cached, and served to the standard building-skin
# renderer via "prefab:<name>" paths. Every placed instance can permute
# door/window pieces by position hash, so no two houses need match.
#
# Layer entry: [piece_path, px_x, px_y] — pack-scale pixel offsets onto
# the bake canvas, hand-tuned against screenshot gates (the kit ships no
# anchor metadata; empirical offsets are the honest approach).
# RENDER-ONLY: bakes happen at load; nothing here touches the sim.

const W := "res://assets/hd/walls/"
const R := "res://assets/hd/roofs/"

# v1 catalog. Canvas 512x448 at pack scale (2x2-tile huts).
const G := "res://assets/hd/ground/"
const PREFABS := {
	# 2x2 hut: four corner rotations + gable roof. Cell origin for grid
	# (i,j) = (base + (i-j)*64, (i+j)*32); every piece blends at its
	# cell origin (kit convention: art pre-positioned in-canvas).
	"hut_a": {
		"canvas": Vector2i(256, 320),
		"layers": [
			[G + "Ground G1_S.png", 64, 32, 0, 0],
			[G + "Ground G1_S.png", 64, 32, 1, 0],
			[G + "Ground G1_S.png", 64, 32, 0, 1],
			[G + "Ground G1_S.png", 64, 32, 1, 1],
			[W + "Wall A9_E.png", 64, 32, 0, 0],
			[W + "Wall A9_S.png", 64, 32, 1, 0],
			[W + "Wall A9_N.png", 64, 32, 0, 1],
			[R + "Roof A15_S.png", 64, -96, 0, 0],
			[R + "Roof A15_S.png", 64, -96, 1, 0],
			[W + "Wall A9_W.png", 64, 32, 1, 1],
		],
	},
}

static var _cache: Dictionary = {}


static func get_texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var spec: Dictionary = PREFABS.get(name, {})
	if spec.is_empty():
		return null
	var canvas: Vector2i = spec["canvas"]
	var img := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	for layer in spec["layers"]:
		var piece := _load_image(layer[0])
		if piece == null:
			continue
		var px: int = int(layer[1])
		var py: int = int(layer[2])
		if layer.size() >= 5:
			# Grid form: [path, base_x, base_y, i, j] -> cell origin.
			px = int(layer[1]) + (int(layer[3]) - int(layer[4])) * 64
			py = int(layer[2]) + (int(layer[3]) + int(layer[4])) * 32
		img.blend_rect(piece, Rect2i(0, 0, piece.get_width(), piece.get_height()), Vector2i(px, py))
	var tex := ImageTexture.create_from_image(img)
	_cache[name] = tex
	return tex


static func _load_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		if t != null:
			img = t.get_image()
	elif FileAccess.file_exists(path):
		img = Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			return null
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# Dev gate: bake every prefab to a PNG for the screenshot loop.
static func dump_all(out_dir: String) -> void:
	for name in PREFABS:
		var tex := get_texture(name)
		if tex != null:
			tex.get_image().save_png(out_dir + "/prefab_" + name + ".png")
