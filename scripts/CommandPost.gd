class_name CommandPost
extends "res://scripts/Building.gd"

const LOOTER_COST := 50
const LOOTER_BUILD_TIME := 18.0
const SPAWN_OFFSET := Vector2(0, 80)

@export var looter_scene: PackedScene

var _producing := false
var _produce_timer := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("command_post")


func primary_action() -> void:
	if _producing:
		return
	if not GameState.can_spend(LOOTER_COST):
		return
	GameState.spend(LOOTER_COST)
	_producing = true
	_produce_timer = LOOTER_BUILD_TIME


func has_action() -> bool:
	return true


func get_action_button_text() -> String:
	if _producing:
		return "Looter... %.0fs" % _produce_timer
	return "Build Looter (%d Salvage)" % LOOTER_COST


func get_action_available() -> bool:
	if _producing:
		return false
	return GameState.can_spend(LOOTER_COST)


func _process(delta: float) -> void:
	if _producing:
		_produce_timer -= delta
		if _produce_timer <= 0:
			_spawn_looter()
			_producing = false


func _spawn_looter() -> void:
	if looter_scene == null:
		return
	var looter = looter_scene.instantiate()
	looter.position = global_position + SPAWN_OFFSET
	get_parent().add_child(looter)
