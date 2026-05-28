class_name Lootable
extends "res://scripts/Building.gd"

const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const SHAMBLER_SPAWN_INTERVAL := 90.0
const FIRST_SPAWN_MIN_DELAY := 30.0
const INFESTED_BODY_COLOR := Color("3f4a2f")

# Footprint per neighborhood type (px). residential 2x2, commercial 3x2, industrial/institutional 3x3.
const FOOTPRINTS := {
	"residential": Vector2(64, 64),
	"commercial": Vector2(96, 64),
	"industrial": Vector2(96, 96),
	"medical": Vector2(96, 96),
	"security": Vector2(96, 96),
}
const NEIGHBORHOOD_COLORS := {
	"residential": Color("6a5a44"),
	"commercial": Color("5e5a4a"),
	"industrial": Color("44423e"),
	"medical": Color("6e6e68"),
	"security": Color("3a4250"),
}

@export var starting_salvage: int = 200
@export var is_infested: bool = false
@export var neighborhood_type: String = "residential"

var remaining_salvage: int = 0
var _spawn_timer := 0.0


func _ready() -> void:
	super._ready()
	remaining_salvage = starting_salvage
	add_to_group("lootable")
	var fp: Vector2 = FOOTPRINTS.get(neighborhood_type, Vector2(64, 64))
	size_pixels = fp
	var shape := RectangleShape2D.new()
	shape.size = fp
	($CollisionShape as CollisionShape2D).shape = shape
	if is_infested:
		body_color = INFESTED_BODY_COLOR
		_spawn_timer = randf_range(FIRST_SPAWN_MIN_DELAY, SHAMBLER_SPAWN_INTERVAL)
	else:
		body_color = NEIGHBORHOOD_COLORS.get(neighborhood_type, body_color)
	queue_redraw()


func take_salvage(amount: int) -> int:
	var taken: int = min(amount, remaining_salvage)
	remaining_salvage -= taken
	if remaining_salvage <= 0:
		queue_free()
	return taken


func _process(delta: float) -> void:
	if not is_infested:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0:
		_spawn_timer = SHAMBLER_SPAWN_INTERVAL
		_spawn_shambler()


func _spawn_shambler() -> void:
	var s = SHAMBLER_SCENE.instantiate()
	var jitter := Vector2(randf_range(-30, 30), randf_range(-30, 30))
	s.position = global_position + jitter
	get_parent().add_child(s)


func _draw_building_icon() -> void:
	var icon_color: Color = PALETTE_ICON_NEUTRAL
	match neighborhood_type:
		"commercial":
			var s := Vector2(10.0, 10.0)
			draw_rect(Rect2(-s / 2.0, s), icon_color)
		"medical":
			draw_line(Vector2(-6, 0), Vector2(6, 0), icon_color, 2.0, true)
			draw_line(Vector2(0, -6), Vector2(0, 6), icon_color, 2.0, true)
		_:
			draw_circle(Vector2.ZERO, 5.0, icon_color)
