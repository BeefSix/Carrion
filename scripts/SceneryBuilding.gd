extends "res://scripts/Building.gd"

# Regular building — the third building category (Matt directive
# 2026-06-10, MAP_DESIGN.md): NO use. Not lootable, not infested, no
# actions. Pure map material: collision (chokes + lanes), iso silhouette
# (readability), noise occlusion (it's in the buildings group, which
# NoiseField's occluder pass reads). Most of a city is scenery — that's
# what makes the lootable minority legible.
#
# Destructible like any building (siege-clearing a wall of row homes is
# legitimate play and costs time + noise), but nothing drops.

const LootableScript := preload("res://scripts/Lootable.gd")

@export var neighborhood_type: String = "residential"


func _ready() -> void:
	# Reuse the Lootable visual identity (footprints + muted district
	# palette) so districts read coherently, with a slight darkening so
	# scenery sits BEHIND lootables perceptually.
	var fp: Vector2 = LootableScript.FOOTPRINTS.get(neighborhood_type, Vector2(64, 64))
	size_pixels = fp
	var col: Color = LootableScript.NEIGHBORHOOD_COLORS.get(neighborhood_type, body_color)
	body_color = col.darkened(0.12)
	var shape := RectangleShape2D.new()
	shape.size = fp
	($CollisionShape as CollisionShape2D).shape = shape
	super._ready()
	add_to_group("scenery_buildings")


func _draw_building_icon() -> void:
	pass  # no icon — no use, nothing to advertise


func _get_skin_path() -> String:
	return LootableScript.SKIN_BY_TYPE.get(neighborhood_type, "")


func _get_skin_modulate() -> Color:
	# Slightly darker than lootables so scenery reads as background.
	return Color(0.82, 0.82, 0.82)
