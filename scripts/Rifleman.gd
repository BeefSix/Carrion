extends "res://scripts/Unit.gd"

const ATTACK_RANGE := 213.0
const ATTACK_DAMAGE := 12
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 10.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

# Projectile config: small yellow bullet. Speed is 2x the firer's move_speed
# (computed at fire time) so each bullet visibly outpaces the shooter but
# stays slow enough to track. Rifleman at 80 move_speed -> 160 px/s bullets.
const PROJECTILE_COLOR := Color(0.95, 0.78, 0.35)
# Base accuracy in degrees. Lower = tighter cone. Squad accuracy bonus (from
# leadership aura) reduces effective spread multiplicatively:
# effective_spread = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus).
const BASE_ACCURACY_DEG := 4.0

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
# Threat-scan cache. Was previously per-frame (60 Hz) via
# _find_nearest_threat_in_range, iterating units + corpses groups for every
# combat unit in IDLE state. At 30 idle units + 200 zombies that's ~360K
# iterations/sec just for kite-from-threat detection. 5 Hz polling preserves
# the gameplay behavior - kite reaction within 0.2s is plenty.
const THREAT_CHECK_INTERVAL := 0.2
var _threat_check_timer: float = 0.0
var _threat_cached = null

# Sprite animation state. Pixellab gives 8 cardinal+diagonal facings; we pick
# one per frame by projecting facing_dir into iso screen space (the game's
# 4:3 oblique projection rotates world axes 45deg in screen space).
const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const SPRITE_ROOT := "res://assets/sprites/units/military/rifleman/"
# Hold attack animation for a beat after firing so it visibly plays instead
# of snapping back to idle/walk on the next physics tick.
const ATTACK_ANIM_HOLD := 0.35
var _attack_anim_timer: float = 0.0


func _ready() -> void:
	super._ready()
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frames := _build_sprite_frames()
	if frames.get_animation_names().is_empty():
		return
	sprite.sprite_frames = frames
	use_sprite = true
	sprite.play(&"idle_south")


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		elif stance == Stance.AGGRESSIVE:
			_try_shoot_in_range(delta)
		return

	if stance == Stance.PASSIVE:
		velocity = Vector2.ZERO
		return

	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null:
		_kite_from(threat)
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise()


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: keep the nav target, but fire opportunistically at
	# anything in ATTACK_RANGE. No kiting (we honor the move order). Reuses the
	# same cooldown/retarget cadence as the idle attack path.
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_zombie()
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD
		_emit_shot_noise()


func _fire_at(target) -> void:
	# Spawns a direct-fire projectile. Damage resolves on impact, not here.
	# Noise still fires at the call site (fire-time, per the projectile spec).
	_attack_anim_timer = ATTACK_ANIM_HOLD
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus)
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": move_speed * 4.0,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.BULLET,
		"color": PROJECTILE_COLOR,
		"visual_width": 2.5,  # bullet radius in px
	})


func _find_nearest_zombie():
	# Despite the legacy name, this targets ANY hostile unit. Routed through
	# GameState.is_hostile so the Military mirror (player Military vs AI
	# Military) works - the previous faction-equality skip dropped same-faction
	# enemies and the two armies walked through each other (AUDIT H4). Falls
	# back to the nearest opposing HQ when no hostile unit is in range so
	# units posted at the enemy base auto-attack for the win condition.
	var best = null
	var best_dist := ATTACK_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(ATTACK_RANGE)


func _find_nearest_hostile_hq(range_px: float):
	# Opposing HQ = HQ tagged with the ownership group opposite to ours.
	var enemy_group: String = "player_buildings" if is_in_group("ai_units") else "ai_buildings"
	var best = null
	var best_dist := range_px
	for b in get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(b):
			continue
		if not b.is_in_group("hq"):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d <= best_dist:
			best_dist = d
			best = b
	return best


func _find_nearest_threat_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d <= best_dist:
			best_dist = d
			best = c
	return best


func _kite_from(threat) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * KITE_SPEED
	move_and_slide()


func _emit_shot_noise() -> void:
	NoiseBus.emit(global_position, NOISE_PER_SHOT)


func _update_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif _attack_anim_timer > 0.0:
		action = "attack"
	elif velocity.length_squared() > 1.0 or current_command == Command.MOVE:
		action = "walk"
	else:
		action = "idle"
	var dir: String = _world_facing_to_sprite_dir(facing_dir)
	var anim_name := "%s_%s" % [action, dir]
	if String(sprite.animation) != anim_name:
		sprite.play(anim_name)


func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	# Project world facing into iso screen space (matches the 4:3 oblique
	# transform IsoView applies to positions). The chosen sprite then aligns
	# with how the unit's movement looks on screen, not on the world grid.
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


func _build_sprite_frames() -> SpriteFrames:
	# Walk the on-disk asset tree and assemble a SpriteFrames resource at
	# runtime. Each (action, direction) pair becomes one named animation; we
	# probe sequential frame indices until a missing file ends the cycle.
	# Speeds/loop flags are per-action: attack and death play once, idle and
	# walk loop. Speeds in fps; tuned for readable motion at 32px.
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	var anim_speeds := {"idle": 4.0, "walk": 12.0, "attack": 18.0, "death": 8.0}
	var anim_loops := {"idle": true, "walk": true, "attack": false, "death": false}
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
					sf.set_animation_speed(anim_name, anim_speeds[action])
					sf.set_animation_loop(anim_name, anim_loops[action])
					added_any = true
				sf.add_frame(anim_name, load(frame_path))
				i += 1
	return sf
