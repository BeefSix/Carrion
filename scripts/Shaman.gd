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


func _ready() -> void:
	super._ready()
	_init_shaman_sprite()


# ---- Sprite system (RENDER ONLY — Shaman extends Unit, so it carries its
# own small loader like Walker/Shambler). The attack slot is the ritual
# staff-raise channel, played while Sub.CHANNEL is active. ----------------

const SPRITE_ROOT := "res://assets/sprites/units/tribal/shaman/"
const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const SPRITE_ANIM_SPEEDS := {"idle": 4.0, "walk": 10.0, "attack": 6.0, "death": 8.0}
const SPRITE_ANIM_LOOPS := {"idle": true, "walk": true, "attack": true, "death": false}


func _init_shaman_sprite() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	for action in ["idle", "walk", "attack", "death"]:
		for dir in SPRITE_DIRECTIONS:
			var anim_name := "%s_%s" % [action, dir]
			var added_any := false
			var i := 0
			while true:
				var frame_path := "%s%s/%s/%d.png" % [SPRITE_ROOT, action, dir, i]
				if not ResourceLoader.exists(frame_path):
					break
				if not added_any:
					sf.add_animation(anim_name)
					sf.set_animation_speed(anim_name, SPRITE_ANIM_SPEEDS[action])
					sf.set_animation_loop(anim_name, SPRITE_ANIM_LOOPS[action])
					added_any = true
				sf.add_frame(anim_name, load(frame_path))
				i += 1
	if sf.get_animation_names().is_empty():
		return
	sprite.sprite_frames = sf
	use_sprite = true
	sprite.play(&"idle_south")


# Sanctioned render-side transcendental (same as CombatUnit/Shambler/Walker).
func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


func _update_shaman_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif _sub == Sub.CHANNEL:
		action = "attack"  # the ritual staff-raise loops for the whole channel
	elif velocity.length_squared() > 1.0:
		action = "walk"
	else:
		action = "idle"
	var anim_name := "%s_%s" % [action, _world_facing_to_sprite_dir(facing_dir)]
	if String(sprite.animation) != anim_name:
		sprite.play(anim_name)


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	if use_sprite:
		_update_shaman_sprite_animation()
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
