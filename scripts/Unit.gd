class_name Unit
extends CharacterBody2D

enum Faction { MILITARY, TRIBAL, ZOMBIE, NEUTRAL }
enum Command { IDLE, MOVE, ATTACK, GATHER }

@export var faction: Faction = Faction.MILITARY
@export var max_hp: int = 100
@export var body_color: Color = Color.WHITE

var current_hp: int
var current_command: Command = Command.IDLE


func _ready() -> void:
	current_hp = max_hp
	($Body as Polygon2D).color = body_color


func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	queue_redraw()
	if current_hp == 0:
		_die()


func _die() -> void:
	queue_free()


func _draw() -> void:
	var bar_width := 24.0
	var bar_height := 4.0
	var bar_y := -20.0
	var x := -bar_width / 2.0
	draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.15, 0.05, 0.05))
	var fill_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), Color(0.3, 0.8, 0.3))
