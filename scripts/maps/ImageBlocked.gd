extends StaticBody2D

# Invisible nav/collision blocker for image-first maps (pond, debris
# fields, the boundary fence). In the "buildings" group so the nav bake
# sees it; nav_poly_world gives the exact inverse-projected footprint.
# Renders nothing — the obstacle's art is baked into the backdrop.

var nav_poly_world: PackedVector2Array = PackedVector2Array()
var size_pixels: Vector2 = Vector2(64, 64)  # rect fallback for the bake


func _ready() -> void:
	add_to_group("buildings")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size_pixels
	shape.shape = rect
	add_child(shape)
