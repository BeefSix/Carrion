extends "res://scripts/Unit.gd"

enum Sub { NONE, GATHER_APPROACH, GATHER_CHANNEL, GATHER_RETURN, HARVEST_APPROACH, HARVEST_CHANNEL }

const SALVAGE_PER_TRIP := 25
const CHANNEL_TIME := 3.0
const INTERACTION_RANGE := 80.0
# Widened 1000 -> 2000 (A4 lab finding): two Walkers drain every lootable
# within 1000px of the camp in ~2 sim-minutes, then idle forever — the
# Tribal AI's income froze mid-match. Walkers are auto-seekers by design;
# the wider net keeps them working as the local patch depletes. FEEL FLAG:
# player Walkers also roam farther before idling (less micro, but they
# wander deeper into the map on their own).
const SEARCH_RADIUS := 2000.0
# H13: when no lootable is in range, hold off the next scan for this long
# instead of re-iterating the lootable group every physics frame.
const LOOTABLE_RETRY_INTERVAL := 1.0
const HARVEST_TIME := 3.0
const HARVEST_RANGE := 60.0

var _sub: Sub = Sub.NONE
var _target_lootable = null
# B3 harvest-the-dead (CALLER_PLAN): Walkers channel on zombie Remains and
# convert them to salvage — the Tribal economy finally engages the
# ecosystem instead of ignoring it. Channel is shorter than a gather trip
# (the pile is right there); yield comes from the Remains node.
var _target_remains = null
var _home_base = null
var _channel_timer := 0.0
var _carrying := 0
var _lootable_retry_timer: float = 0.0


func _ready() -> void:
	super._ready()
	# Load-bearing: Shambler.gd's perception filter exempts the "walkers"
	# group from targeting — this is what makes Walker "stroll through a
	# horde untouched" (DESIGN_MASTER §7.2). Without this line, Walkers
	# get eaten on contact and the Tribal economy collapses.
	add_to_group("walkers")
	_init_walker_sprite()


# ---- Sprite system (RENDER ONLY — Walker extends Unit, not CombatUnit,
# so it carries its own small loader like Shambler does). The gather slot
# replaces attack: the Walker's verbs are walk, stoop, carry. ------------

const SPRITE_ROOT := "res://assets/sprites/units/tribal/walker/"
const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const SPRITE_ANIM_SPEEDS := {"idle": 4.0, "walk": 10.0, "gather": 6.0, "death": 8.0}
const SPRITE_ANIM_LOOPS := {"idle": true, "walk": true, "gather": true, "death": false}


func _init_walker_sprite() -> void:
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


# Sanctioned render-side transcendental (same as CombatUnit/Shambler).
func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


func _update_walker_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif _sub == Sub.GATHER_CHANNEL or _sub == Sub.HARVEST_CHANNEL:
		action = "gather"  # the stoop reads for both verbs
	elif velocity.length_squared() > 1.0:
		action = "walk"
	else:
		action = "idle"
	var anim_name := "%s_%s" % [action, _world_facing_to_sprite_dir(facing_dir)]
	if String(sprite.animation) != anim_name:
		sprite.play(anim_name)


func gather_from(lootable) -> void:
	if lootable == null or not is_instance_valid(lootable):
		return
	_target_lootable = lootable
	_sub = Sub.GATHER_APPROACH
	current_command = Command.GATHER
	_nav.target_position = lootable.position


func harvest_remains(remains) -> void:
	# B3: ordered harvest (right-click a Remains pile).
	if remains == null or not is_instance_valid(remains):
		return
	_target_remains = remains
	_sub = Sub.HARVEST_APPROACH
	current_command = Command.GATHER
	_nav.target_position = remains.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_sub = Sub.NONE
	_target_lootable = null
	_target_remains = null


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	if use_sprite:
		_update_walker_sprite_animation()
	if current_command == Command.MOVE:
		if not _follow_navigation():
			current_command = Command.IDLE
		return

	if _sub == Sub.NONE:
		if _carrying > 0:
			_start_return_home()
		else:
			# H13: cool down between failed lootable scans instead of
			# re-iterating the lootable group every physics frame.
			_lootable_retry_timer = max(0.0, _lootable_retry_timer - delta)
			if _lootable_retry_timer <= 0.0:
				_try_find_lootable()
				if _sub == Sub.NONE:
					_lootable_retry_timer = LOOTABLE_RETRY_INTERVAL

	match _sub:
		Sub.GATHER_APPROACH:
			_tick_gather_approach()
		Sub.GATHER_CHANNEL:
			_tick_gather_channel(delta)
		Sub.GATHER_RETURN:
			_tick_gather_return()
		Sub.HARVEST_APPROACH:
			_tick_harvest_approach()
		Sub.HARVEST_CHANNEL:
			_tick_harvest_channel(delta)
		_:
			velocity = Vector2.ZERO


func _try_find_lootable() -> void:
	var best = null
	var best_dist := SEARCH_RADIUS
	for l in get_tree().get_nodes_in_group("lootable"):
		if not is_instance_valid(l):
			continue
		if l.remaining_salvage <= 0:
			continue
		var d: float = global_position.distance_to(l.position)
		if d <= best_dist:
			best_dist = d
			best = l
	if best == null:
		# B3 auto-harvest fallback: no lootable in reach -> work the nearest
		# Remains instead. The Walker is never idle while the dead are lying
		# around — the 'constantly working the dead' identity.
		var r = _find_nearest_remains()
		if r != null:
			harvest_remains(r)
			return
		velocity = Vector2.ZERO
		return
	_target_lootable = best
	_sub = Sub.GATHER_APPROACH
	_nav.target_position = best.position


func _find_nearest_remains():
	var best = null
	var best_dist := SEARCH_RADIUS
	for r in get_tree().get_nodes_in_group("remains"):
		if not is_instance_valid(r):
			continue
		var d: float = global_position.distance_to(r.position)
		if d <= best_dist:
			best_dist = d
			best = r
	return best


func _tick_harvest_approach() -> void:
	if _target_remains == null or not is_instance_valid(_target_remains):
		_sub = Sub.NONE
		return
	if global_position.distance_to(_target_remains.position) <= HARVEST_RANGE:
		_sub = Sub.HARVEST_CHANNEL
		_channel_timer = HARVEST_TIME
		velocity = Vector2.ZERO
	else:
		_follow_navigation()


func _tick_harvest_channel(delta: float) -> void:
	velocity = Vector2.ZERO
	if _target_remains == null or not is_instance_valid(_target_remains):
		_sub = Sub.NONE
		return
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		var pay: int = _target_remains.harvest()
		if pay > 0:
			_carrying += pay
			MatchStats.log_event(&"harvest", {
				"yield": pay,
				"pos": [global_position.x, global_position.y],
			})
		_target_remains = null
		_sub = Sub.NONE  # next tick: carry triggers return home, or keep working


func _start_return_home() -> void:
	var camp = _find_nearest_camp()
	if camp == null:
		velocity = Vector2.ZERO
		return
	_home_base = camp
	_sub = Sub.GATHER_RETURN
	_nav.target_position = camp.position


func _tick_gather_approach() -> void:
	if _target_lootable == null or not is_instance_valid(_target_lootable):
		_sub = Sub.NONE
		return
	if global_position.distance_to(_target_lootable.position) <= INTERACTION_RANGE:
		_sub = Sub.GATHER_CHANNEL
		_channel_timer = CHANNEL_TIME
		velocity = Vector2.ZERO
	else:
		_follow_navigation()


func _tick_gather_channel(delta: float) -> void:
	velocity = Vector2.ZERO
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		if _target_lootable != null and is_instance_valid(_target_lootable) and _target_lootable.has_method("take_salvage"):
			_carrying += _target_lootable.take_salvage(SALVAGE_PER_TRIP)
		_home_base = _find_nearest_camp()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_sub = Sub.GATHER_RETURN
		_nav.target_position = _home_base.position


func _tick_gather_return() -> void:
	if _home_base == null or not is_instance_valid(_home_base):
		_home_base = _find_nearest_camp()
		if _home_base == null:
			_sub = Sub.NONE
			current_command = Command.IDLE
			return
		_nav.target_position = _home_base.position
	if global_position.distance_to(_home_base.position) <= INTERACTION_RANGE:
		if _carrying > 0:
			# Owner-aware routing via Unit.deposit_salvage so AI-spawned
			# Walkers credit their controller, not GameState.
			deposit_salvage(_carrying)
		_carrying = 0
		_sub = Sub.NONE
		velocity = Vector2.ZERO
		return
	_follow_navigation()


func _find_nearest_camp():
	# Same-ownership preference as Looter._find_nearest_command_post - players
	# return to player's TC, AI Walkers (future Phase 2) return to AI's TC.
	var owner_group: String = "ai_buildings" if is_in_group("ai_units") else "player_buildings"
	var nearest = null
	var nearest_dist := INF
	for c in get_tree().get_nodes_in_group("tribal_camp"):
		if not is_instance_valid(c):
			continue
		if not c.is_in_group(owner_group):
			continue
		var d: float = global_position.distance_to(c.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = c
	if nearest != null:
		return nearest
	# Fallback: any TC.
	for c in get_tree().get_nodes_in_group("tribal_camp"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = c
	return nearest
