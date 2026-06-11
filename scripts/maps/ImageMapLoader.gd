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


# Building-type mapping: pipeline schema types -> Lootable district types
# (drives footprint/salvage tables). Unknowns fall back to residential.
const TYPE_MAP := {
	"grocery_store": "commercial", "commercial": "commercial",
	"house": "residential", "shed": "residential", "tent": "residential",
	"warehouse": "industrial", "solar_array": "industrial", "hangar": "industrial",
	"barracks": "security", "armory": "security",
	"greenhouse": "commercial", "tents": "residential",
}


static func load_map(name: String) -> Dictionary:
	# Two layouts: pipeline folders (assets/maps/<name>/structure.json +
	# source.png, IMAGE_MAP_PLAN schema) and flat files (<name>.json +
	# <name>.png, the Willow Creek prototype schema). Both normalize to
	# the dict Main._load_image_map consumes.
	var folder := "res://assets/maps/" + name + "/structure.json"
	if FileAccess.file_exists(folder):
		return _load_structure_schema(name)
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


static func _load_structure_schema(name: String) -> Dictionary:
	# IMAGE_MAP_PLAN Step 1.4: normalize the pipeline's structure.json.
	var base := "res://assets/maps/" + name
	var jf := FileAccess.open(base + "/structure.json", FileAccess.READ)
	var src = JSON.parse_string(jf.get_as_text())
	jf.close()
	if src == null:
		push_warning("[ImageMap] bad structure.json for %s" % name)
		return {}
	var ms: Array = src.get("map_size", [1408, 768])
	# render_scale (Matt's competitive-size requirement, 2026-06-11):
	# integer nearest-neighbor upscale applied at LOAD — the backdrop
	# sprite scales, and every annotation coordinate multiplies. At 3x a
	# painted person (~14px) matches our 48px unit sprites and the map
	# reaches RTS scale (1408x768 -> 4224x2304) with zero asset work.
	var rs: float = float(src.get("render_scale", 3.0))
	var out := {
		"image_path": base + "/source.png",
		"render_scale": rs,
		# Center the illustration in world space (iso screen coords).
		"screen_origin": [-float(ms[0]) * 0.5 * rs, 1800.0],
		"buildings": [],
		"blocked": [],
		"blocked_polys": [],
		"spawns": {},
		"spawns_by_faction": {},
		"territories": src.get("faction_territories", []),
	}
	for b in src.get("buildings", []):
		var f: Array = b["footprint"]
		out["buildings"].append({
			"c": [(float(f[0]) + float(f[2]) * 0.5) * rs, (float(f[1]) + float(f[3]) * 0.5) * rs],
			"w": float(f[2]) * rs, "h": float(f[3]) * rs,
			"type": TYPE_MAP.get(str(b.get("type", "house")), "residential"),
			"infested": bool(b.get("infested", false)),
			"hp": int(b.get("hp", 200)),
		})
	# Water is impassable terrain (the bridge corridors are the gaps the
	# annotation left between segments); UI zones and blocking wrecks too.
	for tr in src.get("terrain_regions", []):
		if str(tr.get("type", "")) == "water":
			out["blocked_polys"].append(_scale_poly(tr["polygon"], rs))
	for bu in src.get("blocked_ui", []):
		out["blocked_polys"].append(_scale_poly(bu["polygon"], rs))
	for am in src.get("ambient_objects", []):
		if bool(am.get("blocks_movement", false)):
			var p: Array = am["position"]
			out["blocked"].append({"c": [float(p[0]) * rs, float(p[1]) * rs], "w": 44.0 * rs, "h": 26.0 * rs})
	# Faction spawns: player and AI both resolve through their faction.
	for ft in src.get("faction_territories", []):
		var sp: Array = ft["spawn_position"]
		out["spawns_by_faction"][str(ft["faction"])] = [float(sp[0]) * rs, float(sp[1]) * rs]
	# Fallback pair for the generic path.
	if out["spawns_by_faction"].has("military"):
		out["spawns"]["player"] = out["spawns_by_faction"]["military"]
	if out["spawns_by_faction"].has("tribal"):
		out["spawns"]["ai"] = out["spawns_by_faction"]["tribal"]
	return out


static func _scale_poly(poly: Array, rs: float) -> Array:
	var out: Array = []
	for p in poly:
		out.append([float(p[0]) * rs, float(p[1]) * rs])
	return out


static func img_to_world(data: Dictionary, ipx: Vector2) -> Vector2:
	# NOTE: callers pass coords already in RENDER pixels (annotation px x
	# render_scale, done at normalization). screen_origin is render-scaled.
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
