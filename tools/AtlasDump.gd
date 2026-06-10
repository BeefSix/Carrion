extends Node

# Dev tool: build the GroundTiles atlas (with the palette-unification
# remap) and dump it to a PNG for eyeballing without launching the game.
#   godot --headless res://tools/AtlasDump.tscn --path .
# Output: <repo>/atlas_dump.png (gitignored scratch).


func _ready() -> void:
	var gt := TileMapLayer.new()
	gt.set_script(load("res://scripts/GroundTiles.gd"))
	add_child(gt)  # _ready builds the tileset
	var src: TileSetAtlasSource = gt.tile_set.get_source(0)
	var img: Image = src.texture.get_image()
	# Scale x4 for legibility.
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	img.save_png("res://atlas_dump.png")
	print("DUMPED %dx%d" % [img.get_width(), img.get_height()])
	# Fringe atlas too (TerrainKit Phase 1) — composited over mid-gray so
	# the dithered alpha edge is visible.
	var fl: Array = gt.get("_fringe_layers")
	if fl.size() > 0:
		var fsrc: TileSetAtlasSource = fl[0].tile_set.get_source(0)
		var fimg: Image = fsrc.texture.get_image()
		var bg := Image.create(fimg.get_width(), fimg.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(Color(0.35, 0.35, 0.35))
		bg.blend_rect(fimg, Rect2i(0, 0, fimg.get_width(), fimg.get_height()), Vector2i.ZERO)
		bg.resize(bg.get_width() * 4, bg.get_height() * 4, Image.INTERPOLATE_NEAREST)
		bg.save_png("res://fringe_dump.png")
		print("FRINGES DUMPED")
	get_tree().quit(0)
