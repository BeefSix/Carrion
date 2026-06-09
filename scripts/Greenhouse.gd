extends "res://scripts/Building.gd"

const SALVAGE_PER_TICK := 5
const TICK_INTERVAL := 6.0
const ICON_COLOR := Color("4a6638")

var _tick_timer := TICK_INTERVAL


func _ready() -> void:
	super._ready()
	add_to_group("greenhouse")


func _physics_process(delta: float) -> void:
	# D5 (AUDIT 2026-06-09): income tick is sim state — physics tick, not wall frames.
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		GameState.add_salvage(SALVAGE_PER_TICK)


func _draw_building_icon() -> void:
	# Small green square for the plot
	draw_rect(Rect2(-8, -8, 16, 16), ICON_COLOR)
