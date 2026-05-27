class_name Unit
extends CharacterBody2D

enum Faction { MILITARY, TRIBAL, ZOMBIE, NEUTRAL }
enum Command { IDLE, MOVE, ATTACK, GATHER, CONSTRUCT, FLEE }

const MIN_CORPSE_CHANCE := 0.05
const ENGAGEMENT_RANGE := 256.0
const LEVEL2_XP := 50.0
const LEVEL3_XP := 200.0
const HP_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const DAMAGE_MULT_BY_LEVEL := [1.0, 1.0, 1.10, 1.20]
const SPEED_MULT_BY_LEVEL := [1.0, 1.0, 1.0, 1.05]

@export var faction: Faction = Faction.MILITARY
@export var max_hp: int = 100
@export var body_color: Color = Color.WHITE
@export var move_speed: float = 96.0
@export var clean_kills: bool = false
@export var corpse_base_chance: float = 1.0

var current_hp: int
var current_command: Command = Command.IDLE
var selected: bool = false

# Veterancy data (W2 veterancy system)
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
	($Body as Polygon2D).color = body_color


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
	if faction == Faction.ZOMBIE:
		return
	if _is_engaged():
		combat_time += delta
	_update_veterancy()


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
	# Scale current_hp proportionally - no free heal, no caught-at-low-effective-HP.
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
	velocity = to_next.normalized() * get_effective_move_speed()
	move_and_slide()
	return true


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
	if selected:
		draw_circle(Vector2.ZERO, 18.0, Color(1, 1, 0.4), false, 2.0, true)
	var bar_width := 24.0
	var bar_height := 4.0
	var bar_y := -20.0
	var x := -bar_width / 2.0
	draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.15, 0.05, 0.05))
	var max_eff: int = get_effective_max_hp()
	var fill_ratio: float = float(current_hp) / float(max_eff) if max_eff > 0 else 0.0
	draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), Color(0.3, 0.8, 0.3))
	_draw_veterancy_chevrons()


func _draw_veterancy_chevrons() -> void:
	if veterancy_level < 2:
		return
	var count: int = veterancy_level - 1
	var color: Color = Color(0.85, 0.55, 0.2) if veterancy_level == 2 else Color(0.85, 0.85, 0.92)
	var base_x := 14.0
	var base_y := -22.0
	for i in range(count):
		var y: float = base_y - i * 4.0
		var pts := PackedVector2Array([
			Vector2(base_x, y + 3.0),
			Vector2(base_x + 3.0, y),
			Vector2(base_x + 6.0, y + 3.0),
		])
		draw_polyline(pts, color, 1.6, true)
