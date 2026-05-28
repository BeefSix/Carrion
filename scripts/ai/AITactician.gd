class_name AITactician
extends RefCounted

# Tactical layer. Receives a posture order from the strategist (attack a position,
# hold, retreat to base) and translates it into per-unit movement commands using
# the same move_to() API the player uses. Re-evaluated every ~1 second by the
# controller. Auto-attack en route is handled by each unit's existing combat
# behavior — the tactician does NOT override that.

enum Order { HOLD, ATTACK, RETREAT }

var controller: AIController = null
var _order: int = Order.HOLD
var _target_pos: Vector2 = Vector2.ZERO


func set_attack_order(pos: Vector2) -> void:
	_order = Order.ATTACK
	_target_pos = pos


func set_retreat_order(home: Vector2) -> void:
	_order = Order.RETREAT
	_target_pos = home


func set_hold_order() -> void:
	_order = Order.HOLD


func evaluate() -> void:
	if controller == null:
		return
	if _order == Order.HOLD:
		return
	var units: Array = controller.get_combat_units()
	for u in units:
		if not is_instance_valid(u):
			continue
		if not u.has_method("move_to"):
			continue
		u.move_to(_target_pos)


func get_order_name() -> String:
	match _order:
		Order.ATTACK: return "ATTACK"
		Order.RETREAT: return "RETREAT"
		_: return "HOLD"
