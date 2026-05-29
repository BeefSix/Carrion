extends "res://scripts/Unit.gd"

enum ZombieState { IDLE, INVESTIGATE, CHASE, ATTACK }

const VISION_RANGE := 384.0
const ATTACK_RANGE := 36.0
const LOST_TARGET_RANGE := 576.0
const ATTACK_DAMAGE := 8
const ATTACK_PERIOD := 1.0
const RETARGET_INTERVAL := 0.3
const INVESTIGATE_ARRIVE_RANGE := 60.0
const WANDER_RADIUS := 96.0
const WANDER_ARRIVE_RANGE := 30.0
const WANDER_INTERVAL_MIN := 4.0
const WANDER_INTERVAL_MAX := 10.0
const TRIBAL_ALIGNED_COLOR := Color("5a5530")

@export var is_tribal_aligned: bool = false

var _zombie_state: int = ZombieState.IDLE
var _target = null
var _investigate_target: Vector2 = Vector2.ZERO
var _attack_cooldown := 0.0
var _retarget_timer := 0.0
var _wandering := false
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer := 0.0


func _ready() -> void:
	super._ready()
	_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
	if is_tribal_aligned:
		body_color = TRIBAL_ALIGNED_COLOR
		queue_redraw()


func _draw() -> void:
	# Hunched / slumped variant of the humanoid silhouette. Shorter body,
	# wider shoulders sloping in, head pushed slightly forward and down,
	# no lightened head (decayed skin reads as uniform with the body), no
	# facing wedge (zombies don't intentionally face anything). Spec's
	# "hunched, slumped, slow-looking" was deferred from Phase 5; this is
	# the polish pass that lands it.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	var scale: float = float(size_px) / 22.0
	var sw: float = 14.0 * scale
	var sh: float = 5.0 * scale
	var bw: float = 10.0 * scale
	var bh: float = 12.0 * scale  # shorter than upright (16)
	var hr: float = 4.0 * scale

	var head_offset_x: float = 1.5 * scale  # head pushed slightly forward
	var head_y: float = -bh - hr * 0.15  # head sits closer to body (less neck)

	# Selection ring
	if selected:
		draw_arc(Vector2(0.0, 1.5), sw * 0.55, 0.0, TAU, 24, Color(1, 1, 0.4), 1.4, true)

	# Shadow - slightly larger to suggest a sprawled posture.
	draw_colored_polygon(
		_ellipse_polygon(Vector2(0.0, 1.5), sw * 0.55, sh * 0.55),
		Color(0, 0, 0, 0.42),
	)

	# Body silhouette - wider at shoulders, sloping in. Slumped trapezoid.
	# Shoulders sit higher than the head's vertical center to suggest hunched.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-bw * 0.55, -bh + 3.0),  # top-left shoulder, pushed in slightly
		Vector2(bw * 0.55, -bh + 3.0),   # top-right shoulder
		Vector2(bw * 0.45, -1.0),        # bottom-right
		Vector2(-bw * 0.45, -1.0),       # bottom-left
	]), body_color)

	# Head - same color as body for the uniform decayed look, offset forward.
	draw_circle(Vector2(head_offset_x, head_y), hr, body_color)

	# HP bar above (when damaged)
	var max_eff: int = get_effective_max_hp()
	if max_eff > 0 and current_hp < max_eff:
		var bar_w: float = max(18.0, float(size_px) * 0.9)
		var bar_y: float = head_y - hr - 5.0
		var bar_x: float = -bar_w * 0.5
		draw_rect(Rect2(bar_x, bar_y, bar_w, 2.5), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_eff)
		draw_rect(Rect2(bar_x, bar_y, bar_w * fill_ratio, 2.5), Color(0.35, 0.65, 0.3))


func investigate(world_pos: Vector2) -> void:
	if _zombie_state == ZombieState.CHASE or _zombie_state == ZombieState.ATTACK:
		return
	if _zombie_state == ZombieState.INVESTIGATE and _investigate_target.distance_to(world_pos) < 50.0:
		return
	_investigate_target = world_pos
	_zombie_state = ZombieState.INVESTIGATE
	_wandering = false
	_nav.target_position = world_pos


func _physics_process(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_update_target()
		if _target != null and _zombie_state == ZombieState.CHASE:
			_nav.target_position = _target.global_position

	match _zombie_state:
		ZombieState.IDLE:
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_wandering = false
				_nav.target_position = _target.global_position
				return
			_tick_wander(delta)
		ZombieState.INVESTIGATE:
			if _target != null:
				_zombie_state = ZombieState.CHASE
				_nav.target_position = _target.global_position
			elif global_position.distance_to(_investigate_target) <= INVESTIGATE_ARRIVE_RANGE:
				_zombie_state = ZombieState.IDLE
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		ZombieState.CHASE:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			var dist := global_position.distance_to(_target.global_position)
			if dist <= ATTACK_RANGE:
				_zombie_state = ZombieState.ATTACK
				velocity = Vector2.ZERO
			else:
				_follow_navigation()
		ZombieState.ATTACK:
			if _target == null or not is_instance_valid(_target):
				_zombie_state = ZombieState.IDLE
				return
			var dist := global_position.distance_to(_target.global_position)
			if dist > ATTACK_RANGE * 1.2:
				_zombie_state = ZombieState.CHASE
				return
			velocity = Vector2.ZERO
			if _attack_cooldown <= 0:
				if _target.has_method("take_damage"):
					_target.take_damage(get_effective_damage(ATTACK_DAMAGE), self)
				_attack_cooldown = ATTACK_PERIOD


func _tick_wander(delta: float) -> void:
	if _wandering:
		if global_position.distance_to(_wander_target) <= WANDER_ARRIVE_RANGE or _nav.is_navigation_finished():
			_wandering = false
			_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
			velocity = Vector2.ZERO
		else:
			_follow_navigation()
	else:
		velocity = Vector2.ZERO
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_start_wander()


func _start_wander() -> void:
	var offset := Vector2(randf_range(-WANDER_RADIUS, WANDER_RADIUS), randf_range(-WANDER_RADIUS, WANDER_RADIUS))
	var target := global_position + offset
	target.x = clamp(target.x, 50.0, 6094.0)
	target.y = clamp(target.y, 50.0, 6094.0)
	_wander_target = target
	_wandering = true
	_nav.target_position = _wander_target


func _update_target() -> void:
	var best = null
	var best_dist := VISION_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == Faction.ZOMBIE or u.faction == Faction.TRIBAL:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	_target = best
