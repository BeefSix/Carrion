extends "res://scripts/Building.gd"

const SALVAGE_PER_TICK := 4
const TICK_INTERVAL := 6.0
const ICON_COLOR := Color("3a4f6a")

var _tick_timer := TICK_INTERVAL


func _ready() -> void:
	super._ready()
	add_to_group("water_collection")


func _process(delta: float) -> void:
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		GameState.add_salvage(SALVAGE_PER_TICK)


func _draw_building_icon() -> void:
	# Small blue circle for the cistern
	draw_circle(Vector2.ZERO, 7.0, ICON_COLOR)
