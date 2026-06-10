extends Node

# Single chokepoint for every gameplay-affecting command issued by either a
# player or an AI controller. Per NETCODE.md: lockstep multiplayer ships the
# input stream; this is where that stream is collected.
#
# Usage:
#   CommandBus.issue("move", unit, {"target": world_pos})
#   CommandBus.issue("attack", unit, {"target_id": enemy.get_instance_id()})
#   CommandBus.issue("build_wall", builder, {"target": snapped_world_pos})
#
# The bus does two things:
#   1. Records the command via ReplayRecorder (when recording is active).
#   2. Dispatches the command to the unit/building via the kind-specific
#      handler in `_dispatch`.
#
# During replay (ReplayRecorder.is_playing), the live `issue` callsite is
# expected to be silenced upstream (SelectionManager early-returns input,
# AI strategist/tactician early-return decisions). The ReplayPlayer pumps
# recorded commands by calling `apply_recorded` instead — same dispatch
# logic, no re-recording.
#
# Adding a new command kind:
#   - Add a branch in `_dispatch` for the kind name.
#   - All callers issue via `CommandBus.issue(kind, ...)` from day one.
#   - Recording schema stays stable as long as args are JSON-serializable.

# Source tag — recorded alongside each command. Lets analysis tools split
# player input vs AI controllers without parsing args.
const SRC_PLAYER := "player"
const SRC_AI_PLAYER_SLOT := "ai_player_slot"
const SRC_AI_OPPOSING := "ai_opposing"


func issue(kind: String, actor, args: Dictionary, src: String = SRC_PLAYER) -> void:
	# Issue a command live: record (if recording) + dispatch.
	if actor == null or not is_instance_valid(actor):
		return
	# Record before dispatch so the recorded ordering matches issuance order,
	# regardless of any side effects in the dispatch path.
	if ReplayRecorder != null and ReplayRecorder.is_recording:
		ReplayRecorder.record_command(kind, actor, args, src)
	_dispatch(kind, actor, args)


func apply_recorded(kind: String, actor, args: Dictionary) -> void:
	# ReplayPlayer entry point — dispatch only, no record. Actor is resolved
	# by ReplayPlayer from the recorded id; passing it in keeps this function
	# pure (no id-table lookups here).
	if actor == null or not is_instance_valid(actor):
		return
	_dispatch(kind, actor, args)


func _dispatch(kind: String, actor, args: Dictionary) -> void:
	# Single dispatch table. Keep this exhaustive: every gameplay command
	# the codebase issues should land in a branch here.
	match kind:
		"move":
			if actor.has_method("move_to"):
				actor.move_to(args.get("target", Vector2.ZERO))
		"attack":
			# Two flavors: target by node ref (passed via args.target) or by
			# instance id (args.target_id) so recorded commands can re-bind.
			var target = args.get("target", null)
			if target != null and actor.has_method("attack"):
				actor.attack(target)
		"cremate":
			if actor.has_method("cremate_target"):
				actor.cremate_target(args.get("target", null))
		"repair":
			if actor.has_method("repair_at"):
				actor.repair_at(args.get("target", null))
		"force_spawn":
			if actor.has_method("force_spawn_at"):
				actor.force_spawn_at(args.get("target", null))
		"whistle":
			# B2: the Caller's herd verb (CALLER_PLAN).
			if actor.has_method("whistle_at"):
				actor.whistle_at(args.get("target", Vector2.ZERO))
		"gather":
			if actor.has_method("gather_from"):
				actor.gather_from(args.get("target", null))
		"build_wall":
			if actor.has_method("build_wall_at"):
				actor.build_wall_at(args.get("target", Vector2.ZERO))
		_:
			push_warning("[CommandBus] unknown command kind: %s" % kind)
