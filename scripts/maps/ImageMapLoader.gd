extends RefCounted

# Image-first map loader (2026-06-11, the pipeline pivot): Matt
# generates reference-quality map IMAGES (iso 2:1, scale-locked via the
# prompt contract); this loads one as the literal visual world and
# inverse-projects a JSON annotation sidecar into gameplay:
#   assets/maps/<name>.png   — the map (iso screen space, 2:1 canvas)
#   assets/maps/<name>.json  — annotations in IMAGE PIXEL coords:
#     screen_origin: [ox, oy]      where the image's top-left sits in
#                                  iso screen space (picks the world spot)
#     spawns: {player:[ix,iy], ai:[ix,iy]}
#     buildings: [{c:[ix,iy], w, h, type, infested, lootable}]
#     blocked: [{c, w, h}]         non-building obstacles (pond, wreck piles)
# Conversion: image px -> screen px (origin offset) -> world via
# IsoView.screen_to_world. Footprint rect corners inverse-project to an
# exact world polygon for nav. All deterministic data; render-only image.

const IMAGE_LOOTABLE := preload("res://scripts/maps/ImageLootable.gd")


static func load_map(name: String) -> Dictionary:
	var base := "res://assets/maps/" + name
	var jf := FileAccess.open(base + ".json", FileAccess.READ)
	if jf == null:
		push_warning("[ImageMap] missing %s.json" % name)
		return {}
	var data = JSON.parse_string(jf.get_as_text())
	jf.close()
	if data == null:
		push_warning("[ImageMap] bad JSON for %s" % name)
		return {}
	data["image_path"] = base + ".png"
	return data


static func img_to_world(data: Dictionary, ipx: Vector2) -> Vector2:
	var o: Array = data.get("screen_origin", [0, 0])
	return IsoView.screen_to_world(Vector2(float(o[0]), float(o[1])) + ipx)


static func rect_world_poly(data: Dictionary, c: Vector2, w: float, h: float) -> PackedVector2Array:
	# Image-space rect -> exact world polygon (a rotated quad).
	var half := Vector2(w * 0.5, h * 0.5)
	return PackedVector2Array([
		img_to_world(data, c + Vector2(-half.x, -half.y)),
		img_to_world(data, c + Vector2(half.x, -half.y)),
		img_to_world(data, c + Vector2(half.x, half.y)),
		img_to_world(data, c + Vector2(-half.x, half.y)),
	])


static func boundary_polys(data: Dictionary, img_w: float, img_h: float) -> Array:
	# Four thin obstruction strips just outside the image edges — the
	# nav fence that keeps units inside the painting.
	const T := 64.0
	var out: Array = []
	for r in [
		[Vector2(img_w * 0.5, -T * 0.5), img_w + 2 * T, T],
		[Vector2(img_w * 0.5, img_h + T * 0.5), img_w + 2 * T, T],
		[Vector2(-T * 0.5, img_h * 0.5), T, img_h + 2 * T],
		[Vector2(img_w + T * 0.5, img_h * 0.5), T, img_h + 2 * T],
	]:
		out.append(rect_world_poly(data, r[0], r[1], r[2]))
	return out
