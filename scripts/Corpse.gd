extends Node2D

const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const SIZE := Vector2(16, 16)
const ENHANCED_BODY_COLOR := Color(0.5, 0.28, 0.18, 1)

@export var original_max_hp: int = 60
@export var return_delay: float = 42.0

var _timer := 0.0
var _initial_delay := 0.0


func _ready() -> void:
	_initial_delay = return_delay
	_timer = return_delay
	add_to_group("corpses")
	queue_redraw()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_rise()
	else:
		queue_redraw()


func _rise() -> void:
	var z = SHAMBLER_SCENE.instantiate()
	z.position = position
	z.max_hp = original_max_hp
	z.body_color = ENHANCED_BODY_COLOR
	get_parent().add_child(z)
	queue_free()


func _draw() -> void:
	var half := SIZE / 2.0
	draw_rect(Rect2(-half, SIZE), Color(0.18, 0.1, 0.08))
	var bar_width: float = 16.0
	var bar_height := 2.0
	var bar_y := -14.0
	var x: float = -bar_width / 2.0
	var fill_ratio: float = clamp(_timer / _initial_delay, 0.0, 1.0) if _initial_delay > 0.0 else 0.0
	draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.25, 0.05, 0.05))
	draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), Color(0.7, 0.3, 0.18))
