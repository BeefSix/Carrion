class_name Building
extends StaticBody2D

const PALETTE_STRUCTURE := Color("4a4339")
const PALETTE_MILITARY := Color("5a6644")
const PALETTE_SURVIVOR := Color("7a5c3c")
const PALETTE_TRIBAL := Color("8a6a3a")
const PALETTE_ICON_NEUTRAL := Color("8a857a")

@export var max_hp: int = 1000
@export var body_color: Color = Color.WHITE
@export var size_pixels: Vector2 = Vector2(64, 64)

var current_hp: int
var selected: bool = false


func _ready() -> void:
	current_hp = max_hp
	add_to_group("buildings")


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	queue_redraw()
	if current_hp == 0:
		_die()


func get_action_count() -> int:
	return 0


func get_action_text(_idx: int) -> String:
	return ""


func get_action_available(_idx: int) -> bool:
	return false


func do_action(_idx: int) -> void:
	pass


func get_status_text() -> String:
	return ""


func _die() -> void:
	queue_free()


func _draw() -> void:
	var half: Vector2 = size_pixels / 2.0
	# Body
	draw_rect(Rect2(-half, size_pixels), body_color)
	# Type icon (subclass override)
	_draw_building_icon()
	# Selection ring
	if selected:
		draw_rect(Rect2(-half, size_pixels), Color(1, 1, 0.4), false, 3.0)
	# HP bar (only when damaged)
	if current_hp < max_hp:
		var bar_width: float = size_pixels.x
		var bar_height := 4.0
		var bar_y: float = -size_pixels.y / 2.0 - 10.0
		var x: float = -bar_width / 2.0
		draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), Color(0.35, 0.65, 0.3))


func _draw_building_icon() -> void:
	pass
