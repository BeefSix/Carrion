class_name Unit
extends CharacterBody2D

enum Command { IDLE, MOVE, ATTACK, GATHER, CONSTRUCT, FLEE, CREMATE }
# Stance values (3-tier per the squad system design):
#   AGGRESSIVE - engage hostiles in range during MOVE and IDLE
#   NEUTRAL    - engage only while IDLE (don't break formation while moving)
#   PASSIVE    - never engage; hold fire even when idle
# Squad Posture (in Squad.gd) maps directly: AGGRESSIVE -> AGGRESSIVE,
# STANDARD -> NEUTRAL, DEFENSIVE -> PASSIVE.
enum Stance { AGGRESSIVE, NEUTRAL, PASSIVE }

const MIN_CORPSE_CHANCE := 0.05
const ENGAGEMENT_RANGE := 256.0
const CREMATION_RANGE := 48.0
const CREMATION_CHANNEL := 4.0
const LEVEL2_XP := 250.0
const LEVEL3_XP := 1000.0
const HP_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const DAMAGE_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const SPEED_MULT_BY_LEVEL := [1.0, 1.0, 1.0, 1.05]
# Clean-kill chance per veterancy level. On a clean kill the target dies as
# normal but doesn't leave a corpse - i.e. the body is destroyed too
# thoroughly to reanimate. L1 = no clean kills (always corpse), L2 = 10%,
# L3 (fully upgraded) = 18%. Stacks with the existing per-attacker
# clean_kills boolean (Looter magnum); either path suppresses the corpse.
const CLEAN_KILL_CHANCE_BY_LEVEL := [0.0, 0.0, 0.10, 0.18]

const PALETTE_MILITARY := Color("5a6644")
const PALETTE_SURVIVOR := Color("7a5c3c")
const PALETTE_TRIBAL := Color("8a6a3a")
const PALETTE_ZOMBIE := Color("4a5a4a")
const PALETTE_STRUCTURE := Color("4a4339")

@export var faction: GameState.Faction = GameState.Faction.MILITARY
@export var max_hp: int = 100
@export var body_color: Color = Color.WHITE
@export var move_speed: float = 96.0
@export var clean_kills: bool = false
@export var corpse_base_chance: float = 1.0
@export var size_px: int = 22
# When true, the unit scene provides its own AnimatedSprite2D child and the
# procedural body/head/wedge in _draw is skipped. Shadow, selection ring, HP
# bar, and veterancy chevrons still draw (they're gameplay UI, not character
# art). The sprite child gets its position offset to iso screen space per
# frame so it lines up with the iso ground plane like Building visuals do.
@export var use_sprite: bool = false

var current_hp: int
var current_command: Command = Command.IDLE
var selected: bool = false
var facing_dir: Vector2 = Vector2.DOWN
# Per-unit stance. Aggressive (default): combat units engage hostiles in range
# while following a MOVE order. Passive: combat units ignore everything during
# MOVE, only attacking when idle. Squad-level posture (future work) will write
# through to this field.
var stance: Stance = Stance.AGGRESSIVE

# Squad membership. Set/cleared by SquadManager. `commander` is the direct
# superior in the command tree; for non-leaders this is the unit leading
# their sub-tree. Squad leader's commander is null.
var squad: Squad = null
var commander = null

# Aura bonuses from squad command-tree ancestors. Computed by
# SquadManager._tick_auras at 5Hz, zeroed when out of range / no chain.
# squad_damage_bonus is multiplicative (0.05 = +5%). squad_accuracy_bonus
# is stored but currently unused - Carrion has no projectile spread.
var squad_damage_bonus: float = 0.0
var squad_accuracy_bonus: float = 0.0

var kills_count: int = 0
var damage_dealt: float = 0.0
var combat_time: float = 0.0
var veterancy_level: int = 1
var hp_mult: float = 1.0
var damage_mult: float = 1.0
var speed_mult: float = 1.0

# Engagement check rate. Previously _is_engaged() ran every _process frame
# (60 Hz) for every non-zombie unit. Each call iterates the full units group,
# making this an O(N^2) per-frame cost - one of the biggest scale-dependent
# loops in the codebase. Polling at 2 Hz preserves XP-tracking accuracy
# (combat_time still accumulates per frame when the cached state is true)
# while dropping the iteration cost by 30x.
const ENGAGEMENT_CHECK_INTERVAL := 0.5
var _engagement_check_timer: float = 0.0
var _engaged_cached: bool = false

# Cremation state - set by cremate_target(), ticked in _process. While
# current_command == CREMATE the subclass _physics_process bails out so the
# unit holds position; the actual countdown lives here in the base class.
var _cremation_target = null
var _cremation_timer: float = 0.0

@onready var _nav: NavigationAgent2D = $NavigationAgent


func _ready() -> void:
	current_hp = max_hp
	if _nav != null and _nav.avoidance_enabled:
		if not _nav.velocity_computed.is_connected(_on_safe_velocity):
			_nav.velocity_computed.connect(_on_safe_velocity)
	# H6 collision-layer scheme. All units stay on layer 1 (physics collisions
	# unchanged). Non-zombie units additionally join layer 3 so the Shambler
	# vision query can mask layer 3 only - the 16-slot intersect_shape cap
	# previously filled with neighboring zombies in clusters, blinding the
	# perception system to real targets. Faction is set by the scene's @export
	# before _ready, so this branch correctly excludes Shamblers.
	if faction != GameState.Faction.ZOMBIE:
		collision_layer = collision_layer | 4


func move_to(world_pos: Vector2) -> void:
	_nav.target_position = world_pos
	current_command = Command.MOVE


func toggle_stance() -> void:
	stance = Stance.PASSIVE if stance == Stance.AGGRESSIVE else Stance.AGGRESSIVE


func set_stance(s: int) -> void:
	stance = s


func cremate_target(corpse) -> void:
	# Walk to the corpse, channel for CREMATION_CHANNEL seconds, then destroy it.
	# Combat-unit-only behavior (Looters/Walkers don't channel) - the dispatcher
	# in SelectionManager already filters by selection.
	if corpse == null or not is_instance_valid(corpse):
		return
	_cremation_target = corpse
	move_to(corpse.global_position)


func _tick_cremation(delta: float) -> void:
	if _cremation_target == null:
		return
	if not is_instance_valid(_cremation_target):
		# Corpse already destroyed (rose, cremated by another unit, etc.) - bail out.
		_cremation_target = null
		if current_command == Command.CREMATE:
			current_command = Command.IDLE
		return
	if current_command == Command.CREMATE:
		_cremation_timer -= delta
		if _cremation_timer <= 0.0:
			if _cremation_target.has_method("cremate"):
				_cremation_target.cremate()
			_cremation_target = null
			current_command = Command.IDLE
		return
	# Not yet channeling - if we've finished moving and we're in range, start.
	if current_command == Command.IDLE:
		var dist: float = global_position.distance_to(_cremation_target.global_position)
		if dist <= CREMATION_RANGE:
			current_command = Command.CREMATE
			_cremation_timer = CREMATION_CHANNEL
			velocity = Vector2.ZERO


func take_damage(amount: int, attacker = null) -> void:
	if current_hp <= 0:
		return
	var actual: int = min(amount, current_hp)
	if attacker != null and is_instance_valid(attacker) and "damage_dealt" in attacker:
		attacker.damage_dealt += float(actual)
	current_hp = max(0, current_hp - amount)
	queue_redraw()
	if current_hp == 0:
		if attacker != null and is_instance_valid(attacker) and "kills_count" in attacker:
			attacker.kills_count += 1
		_die(attacker)


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func get_xp_total() -> float:
	return float(kills_count * 10) + (damage_dealt * 0.1) + (combat_time * 0.5)


func _process(delta: float) -> void:
	if velocity.length_squared() > 1.0:
		facing_dir = velocity.normalized()
		queue_redraw()
	# Iso depth sort: back-to-front by world_x + world_y. Updated every frame
	# because units move; cheap (one multiply + clamp). Zombies sort too, so
	# we do this before the zombie-fast-path early return.
	z_index = IsoView.z_for(global_position)
	# When a sprite child is present, shift it into iso screen space so the
	# pixel-art character lines up with the iso ground tile under the unit.
	# Matches the iso_offset trick used in _draw for procedural visuals.
	if use_sprite:
		var sprite: Node2D = get_node_or_null("AnimatedSprite2D")
		if sprite != null:
			sprite.position = IsoView.world_to_screen(position) - position
	if faction == GameState.Faction.ZOMBIE:
		return
	_tick_cremation(delta)
	# Refresh engagement state at 2 Hz; accumulate combat_time per frame
	# while the cached state is true. Same XP-tracking outcome, 30x less work.
	_engagement_check_timer -= delta
	if _engagement_check_timer <= 0.0:
		_engagement_check_timer = ENGAGEMENT_CHECK_INTERVAL
		_engaged_cached = _is_engaged()
	if _engaged_cached:
		combat_time += delta
	_update_veterancy()


func _is_engaged() -> bool:
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == faction:
			continue
		if u.faction == GameState.Faction.NEUTRAL:
			continue
		if global_position.distance_to(u.global_position) <= ENGAGEMENT_RANGE:
			return true
	return false


func _level_for_xp(xp: float) -> int:
	if xp >= LEVEL3_XP:
		return 3
	if xp >= LEVEL2_XP:
		return 2
	return 1


func _update_veterancy() -> void:
	var new_level: int = _level_for_xp(get_xp_total())
	if new_level == veterancy_level:
		return
	var old_level: int = veterancy_level
	veterancy_level = new_level
	_on_level_up(old_level, new_level)


func _on_level_up(old_level: int, new_level: int) -> void:
	var old_hp_mult: float = hp_mult
	hp_mult = HP_MULT_BY_LEVEL[new_level]
	damage_mult = DAMAGE_MULT_BY_LEVEL[new_level]
	speed_mult = SPEED_MULT_BY_LEVEL[new_level]
	if old_hp_mult > 0.0:
		current_hp = int(round(float(current_hp) * (hp_mult / old_hp_mult)))
	queue_redraw()
	print("[%s] Level up: %d -> %d (HP x%.2f, DMG x%.2f, SPD x%.2f)" % [name, old_level, new_level, hp_mult, damage_mult, speed_mult])
	# If we leveled into the rank-2+ band while our squad was leaderless and
	# scattering, the manager can promote us and end the scatter state.
	if squad != null and new_level >= Squad.SEASONED:
		SquadManager.on_unit_promoted(self)


func get_effective_max_hp() -> int:
	return int(max_hp * hp_mult)


func get_effective_move_speed() -> float:
	return move_speed * speed_mult


func get_effective_damage(base_damage: int) -> int:
	# damage_mult comes from veterancy; squad_damage_bonus is the additive
	# percentage from in-range command-tree ancestors (computed at 5Hz by
	# SquadManager). Both multiply onto the base damage.
	return int(round(base_damage * damage_mult * (1.0 + squad_damage_bonus)))


func _die(attacker = null) -> void:
	# Notify SquadManager before queueing the unit for deletion - the manager
	# needs valid references to clean up commander/squad fields and trigger
	# succession.
	if squad != null:
		SquadManager.on_member_died(self)
	if _should_leave_corpse(attacker):
		_spawn_corpse()
	queue_free()


func _should_leave_corpse(attacker) -> bool:
	if attacker != null and is_instance_valid(attacker):
		# Hard clean_kills (e.g. Looter magnum) - always suppresses corpse.
		if "clean_kills" in attacker and attacker.clean_kills:
			return false
		# Veterancy-based clean kill - L2 10%, L3 18%. Per-kill roll.
		if "veterancy_level" in attacker:
			var lvl: int = attacker.veterancy_level
			if lvl >= 0 and lvl < CLEAN_KILL_CHANCE_BY_LEVEL.size():
				if randf() < CLEAN_KILL_CHANCE_BY_LEVEL[lvl]:
					return false
	if faction != GameState.Faction.MILITARY and faction != GameState.Faction.ZOMBIE:
		return false
	return randf() < corpse_base_chance


func _spawn_corpse() -> void:
	var corpse_scene: PackedScene = load("res://scenes/Corpse.tscn")
	if corpse_scene == null:
		return
	var c = corpse_scene.instantiate()
	c.position = global_position
	c.original_max_hp = max_hp
	c.was_military = (faction == GameState.Faction.MILITARY)
	c.veterancy_at_death = veterancy_level
	c.return_delay = 30.0 + float(max_hp) / 5.0
	get_parent().add_child(c)


func _follow_navigation() -> bool:
	if _nav.is_navigation_finished():
		velocity = Vector2.ZERO
		return false
	var next_pos := _nav.get_next_path_position()
	var to_next := next_pos - global_position
	var desired: Vector2 = to_next.normalized() * get_effective_move_speed()
	if _nav.avoidance_enabled:
		_nav.set_velocity(desired)
		# move_and_slide() happens in _on_safe_velocity callback after RVO compute.
	else:
		velocity = desired
		move_and_slide()
	return true


func _on_safe_velocity(safe_v: Vector2) -> void:
	velocity = safe_v
	move_and_slide()


func _physics_process(_delta: float) -> void:
	if current_command != Command.MOVE:
		return
	if not _follow_navigation():
		current_command = Command.IDLE


func get_action_count() -> int:
	return 0


func get_action_text(_idx: int) -> String:
	return ""


func get_action_available(_idx: int) -> bool:
	return false


func do_action(_idx: int) -> void:
	pass


func get_status_text() -> String:
	return ""


func _draw() -> void:
	# Iso shift - the unit's node stays at world coords (so nav, physics,
	# range checks all keep working) but the visible silhouette renders at
	# IsoView.world_to_screen(position), where the iso ground tile under
	# that world coord sits. Matches the Building._draw approach.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	# Silhouette geometry scaled by size_px so HG/Brawler look bigger than
	# Looter/Scout without per-subclass overrides.
	var scale: float = float(size_px) / 22.0
	var sw: float = 13.0 * scale  # shadow width
	var sh: float = 5.0 * scale   # shadow height
	var bw: float = 9.0 * scale   # body width
	var bh: float = 16.0 * scale  # body height
	var hr: float = 4.0 * scale   # head radius

	var body_top_y: float = -bh
	var head_y: float = body_top_y - hr * 0.55

	# Selection ring sits on the ground, around the shadow.
	if selected:
		draw_arc(Vector2(0.0, 1.5), sw * 0.55, 0.0, TAU, 24, Color(1, 1, 0.4), 1.4, true)

	# Shadow under the figure - one solid translucent ellipse so the figure
	# reads as resting on the ground plane, not floating.
	draw_colored_polygon(
		_ellipse_polygon(Vector2(0.0, 1.5), sw * 0.5, sh * 0.5),
		Color(0, 0, 0, 0.42),
	)

	# Body silhouette - slight trapezoid, broader at shoulders than waist.
	# All units share this base shape; subclass differentiation comes from
	# body_color, size_px, and (later) overridable accents. Skipped when the
	# subclass uses a sprite (AnimatedSprite2D child handles the character art).
	if not use_sprite:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-bw * 0.42, body_top_y + 2.0),
			Vector2(bw * 0.42, body_top_y + 2.0),
			Vector2(bw * 0.5, -1.0),
			Vector2(-bw * 0.5, -1.0),
		]), body_color)

		# Head - slightly lighter than the body so the silhouette reads.
		draw_circle(Vector2(0.0, head_y), hr, body_color.lightened(0.08))

		# Facing wedge - small lighter triangle on the chest pointing iso-forward.
		# Direction comes from facing_dir (already tracked in _process), projected
		# to iso space so visually it points where the unit "is looking".
		_draw_facing_wedge(body_top_y, bh, bw)

	# HP bar floats above the head when damaged.
	var max_eff: int = get_effective_max_hp()
	if max_eff > 0 and current_hp < max_eff:
		var bar_w: float = max(18.0, float(size_px) * 0.9)
		var bar_y: float = head_y - hr - 5.0
		var bar_x: float = -bar_w * 0.5
		draw_rect(Rect2(bar_x, bar_y, bar_w, 2.5), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_eff)
		draw_rect(Rect2(bar_x, bar_y, bar_w * fill_ratio, 2.5), Color(0.35, 0.65, 0.3))

	# Veterancy chevrons sit above the HP bar (or just above the head when
	# HP is full and the bar is hidden).
	_draw_veterancy_chevrons(head_y - hr - 8.0)


func _draw_facing_wedge(body_top_y: float, bh: float, bw: float) -> void:
	# Project facing_dir (world space) to iso so the wedge points the
	# direction the unit is heading in screen space.
	var iso_facing: Vector2 = Vector2(
		facing_dir.x - facing_dir.y,
		(facing_dir.x + facing_dir.y) * 0.75,
	)
	if iso_facing.length_squared() < 0.001:
		return
	iso_facing = iso_facing.normalized()
	var chest := Vector2(0.0, body_top_y + bh * 0.30)
	var tip: Vector2 = chest + iso_facing * (bw * 0.55)
	var perp: Vector2 = iso_facing.rotated(PI * 0.5) * 1.8
	draw_colored_polygon(PackedVector2Array([
		chest + perp, tip, chest - perp,
	]), body_color.lightened(0.45))


func _draw_veterancy_chevrons(top_y: float) -> void:
	if veterancy_level < 2:
		return
	var count: int = veterancy_level - 1
	var color: Color = Color(0.82, 0.55, 0.22) if veterancy_level == 2 else Color(0.85, 0.85, 0.92)
	var base_x: float = 6.0
	var base_y: float = top_y
	for i in range(count):
		var y: float = base_y - i * 4.0
		var pts := PackedVector2Array([
			Vector2(base_x, y + 3.0),
			Vector2(base_x + 3.0, y),
			Vector2(base_x + 6.0, y + 3.0),
		])
		draw_polyline(pts, color, 1.6, true)


func _ellipse_polygon(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segments := 14
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return pts
