class_name Unit
extends CharacterBody2D

enum Faction { MILITARY, TRIBAL, ZOMBIE, NEUTRAL }
enum Command { IDLE, MOVE, ATTACK, GATHER }

@export var faction: Faction = Faction.MILITARY
@export var max_hp: int = 100
@export var body_color: Color = Color.WHITE
@export var move_speed: float = 96.0

var current_hp: int
var current_command: Command = Command.IDLE
var selected: bool = false

@onready var _nav: NavigationAgent2D = $NavigationAgent


func _ready() -> void:
	current_hp = max_hp
	($Body as Polygon2D).color = body_color


func move_to(world_pos: Vector2) -> void:
	_nav.target_position = world_pos
	current_command = Command.MOVE


func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	queue_redraw()
	if current_hp == 0:
		_die()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func _die() -> void:
	queue_free()


func _physics_process(_delta: float) -> void:
	if current_command != Command.MOVE:
		return
	if _nav.is_navigation_finished():
		current_command = Command.IDLE
		velocity = Vector2.ZERO
		return
	var next_pos := _nav.get_next_path_position()
	var to_next := next_pos - global_position
	velocity = to_next.normalized() * move_speed
	move_and_slide()


func _draw() -> void:
	if selected:
		draw_circle(Vector2.ZERO, 18.0, Color(1, 1, 0.4), false, 2.0, true)
	var bar_width := 24.0
	var bar_height := 4.0
	var bar_y := -20.0
	var x := -bar_width / 2.0
	draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.15, 0.05, 0.05))
	var fill_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), Color(0.3, 0.8, 0.3))
