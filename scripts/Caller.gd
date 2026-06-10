extends "res://scripts/Unit.gd"

# The Caller — Tribal's signature zombie-commander (DESIGN_MASTER §7.2,
# CALLER_PLAN phase B2, HERD model approved 2026-06-10).
#
# One verb: the WHISTLE. Right-click ground within whistle range plants a
# SteeringField attractor at that point and the Caller channels —
# stationary, fragile, the army-scale anchor and the stated faction
# weakness made mechanical. Wild zombies in the emitter's radius drift
# toward the point (a BIAS on wander, not a script — §3.4 grammar; louder
# noise still out-pulls it, killing the Caller ends it instantly).
#
# Distinctness contract (the control ladder): the Hunter WEARS the dead
# (4 owned defensive thralls), the Caller AIMS the dead (unowned mass
# influence), the future Beastmaster KEEPS the dead (owned packs). The
# Caller must never own zombies — nothing here tracks a single zombie.
#
# v1 is SILENT (no NoiseBus): same anti-horde-spawn rationale as the
# thrall redesign. The audible-whistle-as-liability layer returns as a
# deliberate tuned emission when hordes are wanted (flagged, not default).
#
# Caller dies -> queue_free -> _exit_tree removes the emitter -> the herd
# resumes wild behavior wherever it stands. No revert bookkeeping; nothing
# was ever owned. (§7.2 control rule, for free.)

enum Sub { NONE, CHANNELING }

const CALLER_WHISTLE_RANGE_PX := 14.0 * 32.0   # max plant distance (plan §2)
const CALLER_WHISTLE_WEIGHT := 3.0             # attractor strength (lab placeholder)
const CALLER_WHISTLE_RADIUS_PX := 20.0 * 32.0  # influence reach around the point

var _sub: Sub = Sub.NONE
var _whistle_pos: Vector2 = Vector2.ZERO
var _emitter_id: int = -1


# Right-click ground routing (SelectionManager issues "whistle" via
# CommandBus). Within range: plant and channel. Beyond range: walk there
# instead — far click = reposition, close click = aim the dead. Readable.
func whistle_at(world_pos: Vector2) -> void:
	if global_position.distance_to(world_pos) > CALLER_WHISTLE_RANGE_PX:
		move_to(world_pos)
		return
	_stop_whistle()
	_whistle_pos = world_pos
	_sub = Sub.CHANNELING
	current_command = Command.IDLE
	velocity = Vector2.ZERO


func move_to(world_pos: Vector2) -> void:
	# Any move order breaks the channel (the whistle demands stillness).
	_stop_whistle()
	super.move_to(world_pos)


func _stop_whistle() -> void:
	_sub = Sub.NONE
	if _emitter_id != -1:
		SteeringField.remove_emitter(_emitter_id)
		_emitter_id = -1


func _exit_tree() -> void:
	# Death / removal safety net: the influence dies with the Caller,
	# instantly — the §7.2 revert rule with zero bookkeeping.
	if _emitter_id != -1:
		SteeringField.remove_emitter(_emitter_id)
		_emitter_id = -1


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return
	if _sub == Sub.CHANNELING:
		velocity = Vector2.ZERO
		# Plant lazily on the first channeling tick (permanent emitter,
		# removed explicitly — death auto-removes via _exit_tree).
		if _emitter_id == -1:
			_emitter_id = SteeringField.add_emitter(
				_whistle_pos, CALLER_WHISTLE_WEIGHT, CALLER_WHISTLE_RADIUS_PX, -1.0)
		return
	velocity = Vector2.ZERO


func get_status_text_for_hud() -> String:
	if _sub == Sub.CHANNELING:
		return "Whistling — herding the dead..."
	return ""


func _draw() -> void:
	super._draw()
	# Render-only channel telegraph: a faint ring at the whistle point and
	# a line from the Caller, so the player (and the enemy) can read where
	# the herd is being aimed. The Caller is the decapitation target — the
	# telegraph is intentionally visible.
	if _sub != Sub.CHANNELING:
		return
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var to_target: Vector2 = (IsoView.world_to_screen(_whistle_pos) - IsoView.world_to_screen(position))
	draw_line(Vector2.ZERO, to_target, Color(0.85, 0.8, 0.6, 0.25), 1.5, true)
	draw_arc(to_target, 18.0, 0.0, TAU, 24, Color(0.85, 0.8, 0.6, 0.45), 1.5, true)
