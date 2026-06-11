extends Node

# Step 1.3 verifier (IMAGE_MAP_PLAN): render structure.json as a colored
# overlay on the source illustration so extraction accuracy is judged by
# eye and refined. Colors: buildings red (infested = sickly green,
# faction-hinted = faction tints), territories translucent fills, water
# blue, vegetation dark green, roads gray, bridges yellow, ambient cyan,
# blocked-UI magenta.
#   godot --headless res://tools/StructureOverlay.tscn --path . -- --overlay-map=proof_of_concept

const COLORS := {
	"water": Color(0.2, 0.4, 0.9, 0.45),
	"vegetation_dense": Color(0.1, 0.5, 0.15, 0.40),
	"open_ground": Color(0.7, 0.6, 0.3, 0.30),
	"road_network": Color(0.6, 0.6, 0.65, 0.40),
}
const FACTION_COLORS := {
	"military": Color(0.4, 0.9, 0.3, 0.30),
	"survivor": Color(0.95, 0.8, 0.2, 0.30),
	"tribal": Color(0.9, 0.4, 0.15, 0.30),
}


func _ready() -> void:
	var map_name := "proof_of_concept"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--overlay-map="):
			map_name = a.get_slice("=", 1)
	var base := "res://assets/maps/" + map_name
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(base + "/source.png"))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var jf := FileAccess.open(base + "/structure.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(jf.get_as_text())
	jf.close()
	for tr in data.get("terrain_regions", []):
		_fill_poly(img, tr["polygon"], COLORS.get(tr["type"], Color(1, 0, 1, 0.3)))
	for ft in data.get("faction_territories", []):
		_fill_poly(img, ft["polygon"], FACTION_COLORS.get(ft["faction"], Color.WHITE))
		var sp: Array = ft["spawn_position"]
		_box(img, Rect2i(int(sp[0]) - 8, int(sp[1]) - 8, 16, 16), Color(1, 1, 1, 0.95))
	for b in data.get("buildings", []):
		var f: Array = b["footprint"]
		var col := Color(0.95, 0.2, 0.2, 0.85)
		if b.get("infested", false):
			col = Color(0.5, 0.95, 0.2, 0.9)
		elif b.get("faction_hint") != null:
			col = FACTION_COLORS.get(b["faction_hint"], col)
			col.a = 0.9
		_box(img, Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3])), col)
	for st in data.get("structures", []):
		if st.has("polygon"):
			_fill_poly(img, st["polygon"], Color(0.95, 0.9, 0.2, 0.55))
		elif st.has("position"):
			var p: Array = st["position"]
			_box(img, Rect2i(int(p[0]) - 6, int(p[1]) - 6, 12, 12), Color(0.95, 0.9, 0.2, 0.95))
	for am in data.get("ambient_objects", []):
		var p2: Array = am["position"]
		_box(img, Rect2i(int(p2[0]) - 10, int(p2[1]) - 6, 20, 12), Color(0.2, 0.9, 0.9, 0.9))
	for bu in data.get("blocked_ui", []):
		_fill_poly(img, bu["polygon"], Color(0.9, 0.1, 0.9, 0.25))
	img.save_png("res://structure_overlay.png")
	print("[Overlay] saved structure_overlay.png")
	get_tree().quit(0)


func _box(img: Image, r: Rect2i, col: Color) -> void:
	# Outline rectangle, 2px.
	for px in range(maxi(r.position.x, 0), mini(r.position.x + r.size.x, img.get_width())):
		for t in range(2):
			_px(img, px, r.position.y + t, col)
			_px(img, px, r.position.y + r.size.y - 1 - t, col)
	for py in range(maxi(r.position.y, 0), mini(r.position.y + r.size.y, img.get_height())):
		for t in range(2):
			_px(img, r.position.x + t, py, col)
			_px(img, r.position.x + r.size.x - 1 - t, py, col)


func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		var base := img.get_pixel(x, y)
		img.set_pixel(x, y, base.lerp(Color(col.r, col.g, col.b), col.a))


func _fill_poly(img: Image, poly: Array, col: Color) -> void:
	# Scanline fill with alpha blend (small images; fine headless).
	var pts: PackedVector2Array = PackedVector2Array()
	for p in poly:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var min_y: int = img.get_height()
	var max_y: int = 0
	for p in pts:
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	for y in range(maxi(min_y, 0), mini(max_y, img.get_height() - 1) + 1):
		var xs: Array = []
		for i in range(pts.size()):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (float(y) - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			for x in range(maxi(int(xs[k]), 0), mini(int(xs[k + 1]), img.get_width() - 1) + 1):
				var base := img.get_pixel(x, y)
				img.set_pixel(x, y, base.lerp(Color(col.r, col.g, col.b), col.a))
			k += 2
