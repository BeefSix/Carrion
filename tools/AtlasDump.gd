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
	get_tree().quit(0)
