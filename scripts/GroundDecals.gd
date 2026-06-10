extends Node2D

# Ground wear decals (TerrainKit Phase 3, 2026-06-11). RENDER-ONLY.
# One node draws every decal in a single _draw pass — stains, cracks,
# litter, dried blood lying flat ON the ground plane: above the tile +
# fringe layers (z 2), below every unit (units' z_for floor is ~12).
# Top-down splat art is squashed 2:1 onto the iso ground. Flips by
# coordinate hash de-clone repeats; no rotation (keeps the pixel grid).
# Placement comes from MapRecipes' deterministic scatter via Main.

const DECAL_TEXTURES := {
	"oil": "res://assets/props/decal_oil.png",
	"litter": "res://assets/props/decal_litter.png",
	"cracks": "res://assets/props/decal_cracks.png",
	"blood": "res://assets/props/blood_decal.png",
	"deadground": "res://assets/props/decal_deadground.png",
}

var _decals: Array = []  # [{pos: Vector2, tex: Texture2D, flip: bool}]


func _ready() -> void:
	z_index = 2


func set_decals(entries: Array) -> void:
	# entries: [{pos, kind}] from the map recipe. Unknown/missing art is
	# skipped (manifest may name decals before they land).
	_decals.clear()
	var cache: Dictionary = {}
	for e in entries:
		var path: String = DECAL_TEXTURES.get(e["kind"], "")
		if path == "":
			continue
		if not cache.has(path):
			cache[path] = _load_texture(path)
		var tex: Texture2D = cache[path]
		if tex == null:
			continue
		var h: int = (int(e["pos"].x) * 73856093) ^ (int(e["pos"].y) * 19349663)
		_decals.append({"pos": e["pos"], "tex": tex, "flip": (h & 1) == 1, "scale": e.get("scale", 1.0)})
	queue_redraw()


func _load_texture(path: String) -> Texture2D:
	# Dual path (same as GroundTiles): imported resource when available,
	# raw PNG read otherwise — art renders before the editor imports it.
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _draw() -> void:
	for d in _decals:
		var screen: Vector2 = IsoView.world_to_screen(d["pos"])
		var tex: Texture2D = d["tex"]
		var s: Vector2 = tex.get_size()
		var sc: float = d["scale"]
		var flip_x: float = (-1.0 if d["flip"] else 1.0) * sc
		# Squash the top-down splat onto the 2:1 iso ground plane.
		draw_set_transform(screen, 0.0, Vector2(flip_x, 0.5 * sc))
		draw_texture(tex, -s * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
