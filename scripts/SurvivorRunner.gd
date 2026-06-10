extends "res://scripts/Scout.gd"

# Survivor Runner (DESIGN_MASTER §7.3, v1) — "Glenn from The Walking Dead:
# bags and a big knife." The faction's economy unit. The design doc names
# the Scout's energy system as this unit's skeleton, so that's literally
# what this is: Scout's loot loop + sprint/fatigue, re-skinned and tuned
# faster/squishier. The file exists so the SPRITE and the identity have a
# home before connection; deeper Runner verbs (stealth-stab one-shot,
# wounded-carry Courier doctrine) are [PROPOSED] — deferred.
#
# Named SurvivorRunner (not Runner) because the zombie Runner variant owns
# that word in the asset tree (assets/.../zombies/runner) — same reconcile-
# at-integration rule as the Brawler/Brute naming note in memory.
#
# CONNECTED 2026-06-10 (Matt's go): the SettlementHub "runner" row
# replaced the old "scout" row (this class extends Scout, so the
# safehouse-scaled cap carries over via the "scouts" group).

# ---- Sprite system (RENDER ONLY — same pattern as Walker.gd; Scout has no
# sprite substrate of its own, it predates the gold family). The Runner's
# "gather" anim slot maps to the loot channel; attack waits on stealth-stab.
const SPRITE_ROOT := "res://assets/sprites/units/survivor/runner/"
const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const SPRITE_ANIM_SPEEDS := {"idle": 4.0, "walk": 12.0, "gather": 6.0, "death": 8.0}
const SPRITE_ANIM_LOOPS := {"idle": true, "walk": true, "gather": true, "death": false}


func _ready() -> void:
	super._ready()
	_init_runner_sprite()


func _init_runner_sprite() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	for action in ["idle", "walk", "gather", "death"]:
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


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if use_sprite:
		_update_runner_sprite_animation()


# Sanctioned render-side transcendental (same as CombatUnit/Walker).
func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


var _runner_sprite_dir: String = "south"


func _update_runner_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif velocity.length_squared() > 1.0:
		action = "walk"
		_runner_sprite_dir = _world_facing_to_sprite_dir(velocity)
	else:
		action = "idle"
	var anim := "%s_%s" % [action, _runner_sprite_dir]
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != StringName(anim):
		sprite.play(StringName(anim))
