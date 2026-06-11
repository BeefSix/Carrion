extends Node

# Contact-sheet tool (2026-06-11): stitch a glob of pack images into one
# labeled grid PNG so module roles can be decoded in a single view.
#   godot --headless res://tools/ContactSheet.tscn --path . -- --sheet-dir=<abs dir> --sheet-match=<prefix> --sheet-out=<png>

const CELL_W := 128
const CELL_H := 256
const COLS := 8


func _ready() -> void:
	var dir_path := ""
	var match_prefix := ""
	var out := "res://contact_sheet.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sheet-dir="):
			dir_path = a.get_slice("=", 1)
		elif a.begins_with("--sheet-match="):
			match_prefix = a.get_slice("=", 1)
		elif a.begins_with("--sheet-out="):
			out = a.get_slice("=", 1)
	var names: Array = []
	var d := DirAccess.open(dir_path)
	if d != null:
		for f in d.get_files():
			if f.begins_with(match_prefix) and f.ends_with("_S.png"):
				names.append(f)
	names.sort()
	var rows: int = int(ceil(float(names.size()) / float(COLS)))
	var sheet := Image.create(COLS * CELL_W, maxi(rows, 1) * CELL_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.35, 0.38))
	var font_img_unused := 0
	for i in range(names.size()):
		var img := Image.new()
		if img.load(dir_path + "/" + names[i]) != OK:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var cx: int = (i % COLS) * CELL_W
		var cy: int = (i / COLS) * CELL_H
		sheet.blend_rect(img, Rect2i(0, 0, mini(img.get_width(), CELL_W), mini(img.get_height(), CELL_H)), Vector2i(cx, cy))
		# Index marker: a small white tick column per index (count the ticks).
		for t in range(i + 1):
			for py in range(4):
				for px in range(2):
					var tx: int = cx + 2 + (t % 16) * 4 + px
					var ty: int = cy + 2 + (t / 16) * 6 + py
					if tx < sheet.get_width() and ty < sheet.get_height():
						sheet.set_pixel(tx, ty, Color(1, 1, 1))
	sheet.save_png(out)
	print("[Sheet] %d images -> %s" % [names.size(), out])
	get_tree().quit(0)
