extends "res://scripts/Unit.gd"

enum Sub { NONE, APPROACH, CHANNEL }

const FORCE_SPAWN_COST := 40         # Tribal slice default 2026-06-09 — was 25 (too cheap; spammable). Lab-tunable.
const FORCE_SPAWN_CHANNEL_TIME := 7.0 # Tribal slice default — was 5s. Deliberate commit; race-to-interrupt window.
const FORCE_SPAWN_COUNT := 4         # Iconic "small horde from the floorboards." Kept.
const INTERACTION_RANGE := 80.0
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const NoiseFieldScript := preload("res://scripts/NoiseField.gd")

var _sub: Sub = Sub.NONE
var _target_building = null
var _channel_timer := 0.0


func force_spawn_at(building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not (building.is_in_group("lootable") and building.is_infested):
		return
	_target_building = building
	_sub = Sub.APPROACH
	current_command = Command.GATHER
	_nav.target_position = building.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_cancel()


func _cancel() -> void:
	_sub = Sub.NONE
	_target_building = null
	_channel_timer = 0.0


func _physics_process(delta: float) -> void:
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		velocity = Vector2.ZERO
		return

	if _target_building == null or not is_instance_valid(_target_building):
		_cancel()
		current_command = Command.IDLE
		return

	match _sub:
		Sub.APPROACH:
			if global_position.distance_to(_target_building.position) <= INTERACTION_RANGE:
				_sub = Sub.CHANNEL
				_channel_timer = FORCE_SPAWN_CHANNEL_TIME
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		Sub.CHANNEL:
			velocity = Vector2.ZERO
			_channel_timer -= delta
			if _channel_timer <= 0.0:
				_execute_force_spawn()


func _execute_force_spawn() -> void:
	# Owner-aware affordability + spend. An AI-spawned Shaman debits its
	# AIController's pool; a human-player Shaman debits GameState. Pre-fix
	# this hardcoded GameState, which would have drained the human player's
	# pool if the AI ever ran Tribal (currently AI is Military-only, but
	# the hardcoded path was a latent bug per AUDIT M).
	if not can_spend_salvage(FORCE_SPAWN_COST):
		_cancel()
		current_command = Command.IDLE
		return
	if _target_building == null or not is_instance_valid(_target_building):
		_cancel()
		current_command = Command.IDLE
		return
	spend_salvage(FORCE_SPAWN_COST)
	# Per-spawn population cap (2026-06-08). Force-spawn rituals can rip
	# 4 zombies at once; without this gate they'd silently push past the
	# MAX_ZOMBIE_POPULATION ceiling enforced everywhere else. We check
	# inside the loop, not just once, so the count includes zombies
	# spawned earlier in this same ritual. Salvage is spent regardless -
	# the cost is the ritual, not the headcount delivered.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	var center: Vector2 = _target_building.position
	for i in range(FORCE_SPAWN_COUNT):
		if zf != null and zf.has_method("get_zombie_count"):
			if zf.get_zombie_count() >= NoiseFieldScript.MAX_ZOMBIE_POPULATION:
				break
		# SimRng for spawn jitter — gameplay-affecting positions (CLAUDE.md Rule #1).
		var jitter := Vector2(SimRng.randf_range(-32, 32), SimRng.randf_range(-32, 32))
		var s = SHAMBLER_SCENE.instantiate()
		s.position = center + jitter
		if "is_tribal_aligned" in s:
			s.is_tribal_aligned = true
		get_parent().add_child(s)
	_cancel()
	current_command = Command.IDLE


func get_status_text_for_hud() -> String:
	match _sub:
		Sub.APPROACH:
			return "Approaching ritual target..."
		Sub.CHANNEL:
			return "Channeling ritual... %.1fs" % _channel_timer
		_:
			return ""
