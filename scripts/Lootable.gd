class_name Lootable
extends "res://scripts/Building.gd"

const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
const SHAMBLER_SPAWN_INTERVAL := 90.0
const FIRST_SPAWN_MIN_DELAY := 30.0
const INFESTED_BODY_COLOR := Color("3f4a2f")

# Themed shambler variants per neighborhood. Visual is the primary tell; security
# and industrial also get modest stat bumps per the design's "tougher zombies" intent.
const MEDIC_COLOR := Color("9a9590")    # pale gray-white
const POLICE_COLOR := Color("394d6e")   # desaturated dark blue
const BRUTE_COLOR := Color("2f3a2a")    # darker green-brown

const FOOTPRINTS := {
	"residential": Vector2(64, 64),
	"commercial": Vector2(96, 64),
	"industrial": Vector2(96, 96),
	"medical": Vector2(96, 96),
	"security": Vector2(96, 96),
	"civic": Vector2(96, 96),
}
const NEIGHBORHOOD_COLORS := {
	# Per the PZ town-layout / three-quarters perspective spec - muted palette
	# tuned so each district reads distinctly when rendered as iso walls + roof.
	"residential": Color("8a7560"),  # brown-beige
	"commercial": Color("8a8070"),   # gray-tan
	"industrial": Color("454540"),   # dark gray
	"medical": Color("a09595"),      # pale gray-white
	"security": Color("454a55"),     # dark blue-gray
	"civic": Color("a4a08e"),
}

# Per-type salvage anchors. PZ map is denser than the original 22-Lootable
# layout (~70 Lootables now), so per-building yields scale down to keep the
# faction-saturation salvage rate near the design doc's ~600/min target
# instead of the runaway 14k floor that 70 x 200 produced.
const SALVAGE_BY_TYPE := {
	"residential": 50,
	"commercial": 100,
	"industrial": 150,
	"medical": 200,
	"security": 200,
	"civic": 125,
}

# Population threshold for the Lootable shambler spawn. Slightly under
# NoiseField.MAX_ZOMBIE_POPULATION (300) so horde spawns retain headroom and
# the population isn't entirely saturated by Lootables.
const LOOTABLE_SPAWN_POPULATION_CAP := 250

@export var starting_salvage: int = 200
@export var is_infested: bool = false
@export var neighborhood_type: String = "residential"

var remaining_salvage: int = 0
var _spawn_timer := 0.0
# Cached at _ready - DecayField is created once at scene start and never moves.
# Previously _decay_multiplier did a get_first_node_in_group lookup every frame
# from every infested Lootable. With ~30-50 infested at any time, that's
# 30-50 redundant group lookups per frame.
var _decay_field_cached: Node = null
var _zombie_field_cached: Node = null


func _ready() -> void:
	super._ready()
	# Cache field references once. Both autoload-managed singletons that exist
	# for the duration of the match.
	_decay_field_cached = get_tree().get_first_node_in_group("decay_field")
	_zombie_field_cached = get_tree().get_first_node_in_group("zombie_field")
	# Per-type salvage overrides the @export default. Map-placed Lootables
	# inherit from their neighborhood_type; only Lootables created with an
	# explicit @export override (e.g., in tests) keep the 200 default.
	if SALVAGE_BY_TYPE.has(neighborhood_type):
		starting_salvage = SALVAGE_BY_TYPE[neighborhood_type]
	remaining_salvage = starting_salvage
	add_to_group("lootable")
	var fp: Vector2 = FOOTPRINTS.get(neighborhood_type, Vector2(64, 64))
	size_pixels = fp
	var shape := RectangleShape2D.new()
	shape.size = fp
	($CollisionShape as CollisionShape2D).shape = shape
	if is_infested:
		body_color = INFESTED_BODY_COLOR
		_spawn_timer = randf_range(FIRST_SPAWN_MIN_DELAY, SHAMBLER_SPAWN_INTERVAL)
	else:
		body_color = NEIGHBORHOOD_COLORS.get(neighborhood_type, body_color)
	queue_redraw()


func take_salvage(amount: int) -> int:
	var taken: int = min(amount, remaining_salvage)
	remaining_salvage -= taken
	if remaining_salvage <= 0:
		queue_free()
	return taken


func _physics_process(delta: float) -> void:
	# D5 (AUDIT 2026-06-09): infested spawn timer is sim state — physics tick.
	if not is_infested:
		return
	# Spawn rate scales with local decay: 2x at 50+, 3x at 100+ (item 33).
	_spawn_timer -= delta * _decay_multiplier()
	if _spawn_timer <= 0:
		_spawn_timer = SHAMBLER_SPAWN_INTERVAL
		_spawn_shambler()


func _decay_multiplier() -> float:
	if _decay_field_cached == null or not _decay_field_cached.has_method("get_value_at"):
		return 1.0
	var v: float = _decay_field_cached.get_value_at(global_position)
	if v >= 100.0:
		return 3.0
	if v >= 50.0:
		return 2.0
	return 1.0


func _spawn_shambler() -> void:
	# Population cap - previously Lootable spawns bypassed
	# NoiseField.MAX_ZOMBIE_POPULATION because they don't route through the
	# horde-trigger path. With ~30-50 infested Lootables spawning every
	# 30-90s, this produced unbounded population growth that compounded the
	# noise-occlusion cost (cubic in zombie count).
	if _zombie_field_cached != null and _zombie_field_cached.has_method("get_zombie_count"):
		var current_pop: int = _zombie_field_cached.get_zombie_count()
		if current_pop >= LOOTABLE_SPAWN_POPULATION_CAP:
			# Reset the timer so we don't spam this check next frame; try
			# again after the standard interval. Pop should be back below
			# cap by then if it drops.
			return
	var s = SHAMBLER_SCENE.instantiate()
	var jitter := Vector2(randf_range(-30, 30), randf_range(-30, 30))
	s.position = global_position + jitter
	_configure_variant(s)
	get_parent().add_child(s)


func _configure_variant(s) -> void:
	# Set body_color / max_hp / damage_mult BEFORE add_child so Unit._ready picks them up
	# (current_hp = max_hp, body draw uses body_color, attack uses damage_mult).
	match neighborhood_type:
		"medical":
			s.body_color = MEDIC_COLOR
		"security":
			s.body_color = POLICE_COLOR
			s.max_hp = 50
			if "damage_mult" in s:
				s.damage_mult = 1.15
		"industrial":
			s.body_color = BRUTE_COLOR
			s.max_hp = 60
			if "damage_mult" in s:
				s.damage_mult = 1.20
		_:
			pass  # residential / commercial / civic: baseline Shambler


func _draw_building_icon() -> void:
	var icon_color: Color = PALETTE_ICON_NEUTRAL
	match neighborhood_type:
		"commercial":
			# small filled square — shopfront
			var s := Vector2(10.0, 10.0)
			draw_rect(Rect2(-s / 2.0, s), icon_color)
		"medical":
			# cross
			draw_line(Vector2(-6, 0), Vector2(6, 0), icon_color, 2.0, true)
			draw_line(Vector2(0, -6), Vector2(0, 6), icon_color, 2.0, true)
		"industrial":
			# small rectangle with a smokestack stub
			draw_rect(Rect2(Vector2(-7, -3), Vector2(14, 8)), icon_color)
			draw_rect(Rect2(Vector2(3, -8), Vector2(3, 5)), icon_color)
		"security":
			# diamond
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)
			]), icon_color)
		"civic":
			# small upward triangle — gable
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -7), Vector2(7, 6), Vector2(-7, 6)
			]), icon_color)
		_:
			# residential — filled circle
			draw_circle(Vector2.ZERO, 5.0, icon_color)
