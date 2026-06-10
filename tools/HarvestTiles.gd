extends Node

# Reference-harvest tool (2026-06-11): Matt's reference images ARE the
# aesthetic, so the ground tiles come straight out of them. Two modes:
#   --harvest-preview  : dump zoomed crops around candidate centers so
#                        the operator can eyeball clean regions.
#   (default)          : slice final 64x32 patches into the tile dir as
#                        harvest_<terrain>_<n>.png for TERRAIN_PACKS.
# Render-only dev tool; sources stay in assets/concept/.

const REF := "res://assets/concept/ref_suburb.png"
const REF_NIGHT := "res://assets/concept/ref_night.png"
const OUT_DIR := "res://assets/tiles/ground/"

# [terrain, ref, center_x, center_y] — full-res coords. Three offset
# samples per entry become instant pack variants.
var harvest_spots := [
	["yard", REF, 1760, 600],
	["yard", REF, 1980, 700],
	["yard", REF, 1650, 630],
	["road", REF, 320, 1225],
	["road", REF, 260, 1175],
	["road", REF, 1110, 465],
	["sidewalk", REF, 640, 1090],
	["parking", REF, 430, 1190],
	["veg", REF, 1520, 340],
	["deadgrass", REF, 2320, 1235],
]


func _ready() -> void:
	var preview := "--harvest-preview" in OS.get_cmdline_user_args()
	var cache: Dictionary = {}
	var idx := 0
	for spot in harvest_spots:
		var path: String = spot[1]
		if not cache.has(path):
			var img := Image.new()
			img.load(ProjectSettings.globalize_path(path))
			cache[path] = img
		var src: Image = cache[path]
		var cx: int = spot[2]
		var cy: int = spot[3]
		if preview:
			var region := src.get_region(Rect2i(cx - 128, cy - 64, 256, 128))
			region.resize(768, 384, Image.INTERPOLATE_NEAREST)
			region.save_png("res://harvest_preview_%d_%s.png" % [idx, spot[0]])
		else:
			# Three offset 64x32 slices per spot = pack variants.
			for k in range(3):
				var ox: int = cx - 32 + (k - 1) * 40
				var oy: int = cy - 16 + (k - 1) * 14
				var tile := src.get_region(Rect2i(ox, oy, 64, 32))
				tile.save_png(OUT_DIR + "harvest_%s_%d.png" % [spot[0], idx * 3 + k])
		idx += 1
	print("[Harvest] %s done (%d spots)" % ["preview" if preview else "slice", idx])
	get_tree().quit(0)
