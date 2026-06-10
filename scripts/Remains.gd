extends Node2D

# Remains — harvestable zombie leavings (CALLER_PLAN phase B3, approved).
#
# Deliberately NOT a Corpse: corpses are pending zombies (the §4 rise
# economy, humans only — a zombie is already dead and re-rising it was the
# recycle loop removed 2026-06-08). Remains are the TRIBAL resource the
# §3.3/§7.2 design promises: Walkers channel on them and convert the dead
# into economy — the quiet third corpse-verb alongside the Looter's loud
# shoot-to-loot and the Chemist's silent acid. Despawn on a TTL so the
# battlefield doesn't accumulate free money forever; the rise-vs-harvest
# race drama comes from CORPSES, the harvest-vs-rot race from these.

const REMAINS_TTL := 45.0   # sim-seconds before the remains rot away
const SIZE := Vector2(14, 10)
const COLOR_NORMAL := Color("4a4438")
const COLOR_BRUTE := Color("3a3328")

# Set by the spawner (Shambler._die hook) BEFORE add_child.
@export var harvest_yield: int = 8
@export var from_brute: bool = false

var _ttl: float = REMAINS_TTL
var _claimed: bool = false  # a Walker mid-channel owns this pile


func _ready() -> void:
	add_to_group("remains")
	z_index = IsoView.z_for(global_position)
	queue_redraw()


func _physics_process(delta: float) -> void:
	# TTL on the physics tick (sim state — rule #2).
	_ttl -= delta
	if _ttl <= 0.0:
		queue_free()


# Walker channel completion calls this. Returns the yield once; double
# harvesting (two walkers racing) pays only the first.
func harvest() -> int:
	if _claimed:
		return 0
	_claimed = true
	var pay: int = harvest_yield
	queue_free()
	return pay


func _draw() -> void:
	# Render-only: a low dark mound, slightly larger for brutes.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var s: Vector2 = SIZE * (1.5 if from_brute else 1.0)
	var col: Color = COLOR_BRUTE if from_brute else COLOR_NORMAL
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s.x * 0.5, 0), Vector2(-s.x * 0.2, -s.y * 0.6),
		Vector2(s.x * 0.25, -s.y * 0.5), Vector2(s.x * 0.5, 0),
	]), col)
	# Bone fleck — the Tribal-readable tell.
	draw_circle(Vector2(s.x * 0.1, -s.y * 0.3), 1.5, Color(0.8, 0.78, 0.7))
