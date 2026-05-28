extends Node2D

# Lightweight visual prop - car, dumpster, planter, rubble pile. No collision,
# no HP, no behavior. Just a _draw() variant sprite that punctuates ground
# between buildings. Tree-order puts props above ground tiles and below units;
# z_index left at default 0.

enum Kind { CAR, DUMPSTER, PLANTER, RUBBLE_PILE }

@export var kind: int = Kind.CAR
@export var body_color: Color = Color("2a2a2a")
@export var orientation: int = 0  # 0 horizontal, 1 vertical


func _ready() -> void:
	add_to_group("props")
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.CAR:
			_draw_car()
		Kind.DUMPSTER:
			_draw_dumpster()
		Kind.PLANTER:
			_draw_planter()
		Kind.RUBBLE_PILE:
			_draw_rubble_pile()


func _draw_car() -> void:
	# 32x16 dead car silhouette. Body, slightly lighter cabin, two darker windows.
	var size := Vector2(32, 16) if orientation == 0 else Vector2(16, 32)
	var half := size * 0.5
	draw_rect(Rect2(-half, size), body_color)
	# Cabin band
	var cabin: Vector2
	if orientation == 0:
		cabin = Vector2(size.x * 0.55, size.y * 0.6)
	else:
		cabin = Vector2(size.x * 0.6, size.y * 0.55)
	draw_rect(Rect2(-cabin * 0.5, cabin), body_color.lightened(0.12))
	# Windows
	var win: Vector2
	if orientation == 0:
		win = Vector2(size.x * 0.18, size.y * 0.4)
		draw_rect(Rect2(Vector2(-cabin.x * 0.35, -win.y * 0.5), win), Color(0.08, 0.08, 0.10))
		draw_rect(Rect2(Vector2(cabin.x * 0.35 - win.x, -win.y * 0.5), win), Color(0.08, 0.08, 0.10))
	else:
		win = Vector2(size.x * 0.4, size.y * 0.18)
		draw_rect(Rect2(Vector2(-win.x * 0.5, -cabin.y * 0.35), win), Color(0.08, 0.08, 0.10))
		draw_rect(Rect2(Vector2(-win.x * 0.5, cabin.y * 0.35 - win.y), win), Color(0.08, 0.08, 0.10))


func _draw_dumpster() -> void:
	# Small 18x14 dark green/grey bin.
	var size := Vector2(18, 14)
	var half := size * 0.5
	draw_rect(Rect2(-half, size), body_color)
	# Lid strip
	draw_rect(Rect2(-half + Vector2(0, 0), Vector2(size.x, 2.5)), body_color.darkened(0.3))


func _draw_planter() -> void:
	# Round-ish brown planter with green hint on top.
	draw_circle(Vector2(0, 1), 6.5, body_color)
	draw_circle(Vector2(0, -3), 4.5, Color("3a4a35"))


func _draw_rubble_pile() -> void:
	# Irregular pile of broken concrete chunks.
	var c1: Color = body_color
	var c2: Color = body_color.lightened(0.15)
	var c3: Color = body_color.darkened(0.2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, 4), Vector2(-3, -3), Vector2(3, -1), Vector2(6, 5), Vector2(-1, 6)
	]), c1)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, 6), Vector2(-5, 1), Vector2(0, 4), Vector2(-2, 8), Vector2(-8, 8)
	]), c2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(2, 6), Vector2(8, 3), Vector2(10, 7), Vector2(5, 8)
	]), c3)
