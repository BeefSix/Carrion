extends Node2D

const SIZE := Vector2(16, 16)
const BASELINE_ENHANCED_COLOR := Color("6a3a3a")
const L2_ENHANCED_COLOR := Color("583030")
const L3_ENHANCED_COLOR := Color("452626")

const VETERAN_HP_SCALE := { 1: 1.0, 2: 1.25, 3: 1.5 }
const VETERAN_DAMAGE_SCALE := { 1: 1.0, 2: 1.15, 3: 1.25 }

# Preload NoiseField for its MAX_ZOMBIE_POPULATION constant. We use
# the script as the single source of truth for the spawn cap (same
# pattern NoiseField uses for ShamblerScript.HEARING_RANGE_PX). The
# old behavior bypassed the cap and contributed to population overshoot.
const NoiseFieldScript := preload("res://scripts/NoiseField.gd")

# If we hit the rise timer while at the spawn cap, defer and re-check
# every POP_CAP_RETRY_INTERVAL seconds rather than skipping the rise
# outright. The corpse stays on the ground until the population drops
# (cremation / kills / depletion), then rises - the human drama still
# happens, just delayed instead of dropped.
const POP_CAP_RETRY_INTERVAL := 1.0

@export var original_max_hp: int = 60
@export var return_delay: float = 42.0
@export var was_military: bool = false
@export var veterancy_at_death: int = 1
# Full faction at time of death (GameState.Faction). The was_military bool
# above used to be the only ancestry hint; this expands the record so
# telemetry can report e.g. "Tribal corpse rose" once non-Military corpses
# exist. Defaults to NEUTRAL when the spawner doesn't fill it in (older
# call sites or test stubs).
@export var prev_faction: int = GameState.Faction.NEUTRAL

var _timer := 0.0
var _initial_delay := 0.0


var _cremated: bool = false


func _ready() -> void:
	_initial_delay = return_delay
	_timer = return_delay
	add_to_group("corpses")
	# Static z-sort: corpses don't move, so we only set this once.
	z_index = IsoView.z_for(global_position)
	queue_redraw()


func cremate() -> void:
	# Called when a combat unit finishes its 4-sec channel on this corpse.
	# Cancels the return cycle outright - no shambler spawns.
	_cremated = true
	queue_free()


func _process(delta: float) -> void:
	if _cremated:
		return
	_timer -= delta
	if _timer <= 0.0:
		_try_rise()
	else:
		queue_redraw()


func _try_rise() -> void:
	# Bounded by the spawn cap (2026-06-08). Pre-fix, corpse rises ran
	# unconditionally and could push the population well past
	# MAX_ZOMBIE_POPULATION (horde spawns were capped but corpses
	# weren't, so corpse-heavy late-game scenes overshot). Defer if
	# at cap so the rise still lands once the population dips.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombie_count"):
		if zf.get_zombie_count() >= NoiseFieldScript.MAX_ZOMBIE_POPULATION:
			_timer = POP_CAP_RETRY_INTERVAL
			return
	_rise()


func _rise() -> void:
	var shambler_scene: PackedScene = load("res://scenes/units/Shambler.tscn")
	if shambler_scene == null:
		queue_free()
		return
	var z = shambler_scene.instantiate()
	z.position = position
	var hp_scale: float = VETERAN_HP_SCALE.get(veterancy_at_death, 1.0)
	z.max_hp = int(round(float(original_max_hp) * hp_scale))
	if was_military:
		z.body_color = _color_for_level(veterancy_at_death)
	if "damage_mult" in z:
		z.damage_mult = VETERAN_DAMAGE_SCALE.get(veterancy_at_death, 1.0)
	get_parent().add_child(z)
	MatchStats.log_event(&"corpse_rose", {
		"pos": [position.x, position.y],
		"prev_was_military": was_military,
		"prev_faction": GameState.faction_name(prev_faction),
		"veterancy": veterancy_at_death,
		"new_max_hp": z.max_hp,
	})
	queue_free()


func _color_for_level(level: int) -> Color:
	match level:
		3:
			return L3_ENHANCED_COLOR
		2:
			return L2_ENHANCED_COLOR
		_:
			return BASELINE_ENHANCED_COLOR


func _draw() -> void:
	# Iso shift: match Unit/Building _draw so the corpse renders at the iso-projected
	# screen position. Without this the rect draws at raw world coords and ends up
	# offset (visually toward the top of the map) relative to surrounding iso geometry.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	var half := SIZE / 2.0
	draw_rect(Rect2(-half, SIZE), Color(0.14, 0.09, 0.07))
	var bar_width: float = 16.0
	var bar_height := 2.0
	var bar_y := -14.0
	var x: float = -bar_width / 2.0
	var fill_ratio: float = clamp(_timer / _initial_delay, 0.0, 1.0) if _initial_delay > 0.0 else 0.0
	draw_rect(Rect2(x, bar_y, bar_width, bar_height), Color(0.2, 0.05, 0.05))
	var bar_color: Color = Color(0.55, 0.28, 0.22)
	if veterancy_at_death == 2:
		bar_color = Color(0.48, 0.24, 0.2)
	elif veterancy_at_death >= 3:
		bar_color = Color(0.4, 0.2, 0.18)
	draw_rect(Rect2(x, bar_y, bar_width * fill_ratio, bar_height), bar_color)
