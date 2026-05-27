class_name Lootable
extends "res://scripts/Building.gd"

const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const SHAMBLER_SPAWN_INTERVAL := 60.0
const FIRST_SPAWN_MIN_DELAY := 30.0
const INFESTED_BODY_COLOR := Color(0.42, 0.5, 0.3, 1)

@export var starting_salvage: int = 200
@export var is_infested: bool = false

var remaining_salvage: int = 0
var _spawn_timer := 0.0


func _ready() -> void:
	super._ready()
	remaining_salvage = starting_salvage
	add_to_group("lootable")
	if is_infested:
		body_color = INFESTED_BODY_COLOR
		if has_node("Body"):
			($Body as Polygon2D).color = body_color
		_spawn_timer = randf_range(FIRST_SPAWN_MIN_DELAY, SHAMBLER_SPAWN_INTERVAL)


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
