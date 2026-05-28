class_name Unit
extends CharacterBody2D

enum Faction { MILITARY, TRIBAL, ZOMBIE, NEUTRAL, SURVIVOR }
enum Command { IDLE, MOVE, ATTACK, GATHER, CONSTRUCT, FLEE }

const MIN_CORPSE_CHANCE := 0.05
const ENGAGEMENT_RANGE := 256.0
const LEVEL2_XP := 50.0
const LEVEL3_XP := 200.0
const HP_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const DAMAGE_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const SPEED_MULT_BY_LEVEL := [1.0, 1.0, 1.0, 1.05]

const PALETTE_MILITARY := Color("5a6644")
const PALETTE_SURVIVOR := Color("7a5c3c")
const PALETTE_TRIBAL := Color("8a6a3a")
const PALETTE_ZOMBIE := Color("4a5a4a")
const PALETTE_STRUCTURE := Color("4a4339")

@export var faction: Faction = Faction.MILITARY
@export var max_hp: int = 100
@export var body_color: Color = Color.WHITE
@export var move_speed: float = 96.0
@export var clean_kills: bool = false
@export var corpse_base_chance: float = 1.0
@export var size_px: int = 22

var current_hp: int
var current_command: Command = Command.IDLE
var selected: bool = false
var facing_dir: Vector2 = Vector2.DOWN

var kills_count: int = 0
var damage_dealt: float = 0.0
var combat_time: float = 0.0
var veterancy_level: int = 1
var hp_mult: float = 1.0
var damage_mult: float = 1.0
var speed_mult: float = 1.0

@onready var _nav: NavigationAgent2D = $NavigationAgent


func _ready() -> void:
	current_hp = max_hp
	if _nav != null and _nav.avoidance_enabled:
		if not _nav.velocity_computed.is_connected(_on_safe_velocity):
			_nav.velocity_computed.connect(_on_safe_velocity)


func move_to(world_pos: Vector2) -> void:
	_nav.target_position = world_pos
	current_command = Command.MOVE


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
	if faction == Faction.ZOMBIE:
		return
	if _is_engaged():
		combat_time += delta
	_update_veterancy()


func _is_engaged() -> bool:
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if u.faction == faction:
			continue
		if u.faction == Faction.NEUTRAL:
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


func get_effective_max_hp() -> int:
	return int(max_hp * hp_mult)


func get_effective_move_speed() -> float:
	return move_speed * speed_mult


func get_effective_damage(base_damage: int) -> int:
	return int(round(base_damage * damage_mult))


func _die(attacker = null) -> void:
	if _should_leave_corpse(attacker):
		_spawn_corpse()
	queue_free()


func _should_leave_corpse(attacker) -> bool:
	if attacker != null and "clean_kills" in attacker and attacker.clean_kills:
		return false
	if faction != Faction.MILITARY and faction != Faction.ZOMBIE:
		return false
	return randf() < corpse_base_chance


func _spawn_corpse() -> void:
	var corpse_scene: PackedScene = load("res://scenes/Corpse.tscn")
	if corpse_scene == null:
		return
	var c = corpse_scene.instantiate()
	c.position = global_position
	c.original_max_hp = max_hp
	c.was_military = (faction == Faction.MILITARY)
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
	var half: float = float(size_px) / 2.0

	if selected:
		draw_arc(Vector2.ZERO, half + 4.0, 0.0, TAU, 32, Color(1, 1, 0.4), 1.8, true)

	if faction == Faction.ZOMBIE:
		draw_circle(Vector2.ZERO, half, body_color)
	else:
		var size_v := Vector2(size_px, size_px)
		draw_rect(Rect2(-Vector2(half, half), size_v), body_color)
		_draw_facing_triangle(half)

	var bar_width: float = max(20.0, float(size_px))
	var bar_height := 3.0
	var bar_y: float = -half - 7.0
	var bar_x: float = -bar_width / 2.0
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.12, 0.05, 0.05))
	var max_eff: int = get_effective_max_hp()
	var fill_ratio: float = float(current_hp) / float(max_eff) if max_eff > 0 else 0.0
	draw_rect(Rect2(bar_x, bar_y, bar_width * fill_ratio, bar_height), Color(0.35, 0.65, 0.3))

	_draw_veterancy_chevrons(half)


func _draw_facing_triangle(half: float) -> void:
	var tip: Vector2 = facing_dir * (half * 0.85)
	var base_center: Vector2 = facing_dir * (half * 0.2)
	var perp: Vector2 = facing_dir.rotated(PI / 2.0)
	var base_half_width: float = half * 0.35
	var corner_a: Vector2 = base_center + perp * base_half_width
	var corner_b: Vector2 = base_center - perp * base_half_width
	var tri_color: Color = body_color.lightened(0.35)
	draw_colored_polygon(PackedVector2Array([tip, corner_a, corner_b]), tri_color)


func _draw_veterancy_chevrons(half: float) -> void:
	if veterancy_level < 2:
		return
	var count: int = veterancy_level - 1
	var color: Color = Color(0.82, 0.55, 0.22) if veterancy_level == 2 else Color(0.85, 0.85, 0.92)
	var base_x: float = half + 3.0
	var base_y: float = -half - 9.0
	for i in range(count):
		var y: float = base_y - i * 4.0
		var pts := PackedVector2Array([
			Vector2(base_x, y + 3.0),
			Vector2(base_x + 3.0, y),
			Vector2(base_x + 6.0, y + 3.0),
		])
		draw_polyline(pts, color, 1.6, true)
