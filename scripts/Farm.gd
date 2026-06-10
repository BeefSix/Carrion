extends "res://scripts/Building.gd"

# Survivor Farm (DESIGN_MASTER §7.3, v1) — "farms are the pylons." The
# population enabler: Radio Stations only broadcast when attached to a
# friendly Farm (RadioStation checks the "farms" group in radius), and the
# future civilian/recruitment economy hangs off farm count.
#
# CONNECTED 2026-06-10 (Matt's go): the Builder places this via the
# BuildCatalog SURVIVOR table. v1 mechanics: a small supply trickle (subsistence — the
# farm feeds people, people scavenge) so an early farm isn't dead weight.
# The real payoffs (civilian pop cap, recruitment) are the connection
# pass's job. [OPEN per §7.3: civilians as a true second resource.]

const TRICKLE_INTERVAL := 10.0   # sim seconds
const TRICKLE_AMOUNT := 2        # salvage per tick — subsistence, not income

var _trickle_timer: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("farms")


func _physics_process(delta: float) -> void:
	# Fixed-interval accumulator on the physics tick (Rule #2).
	_trickle_timer += delta
	if _trickle_timer >= TRICKLE_INTERVAL:
		_trickle_timer -= TRICKLE_INTERVAL
		_grant_trickle()


func _grant_trickle() -> void:
	# Ownership-routed income: player farms feed GameState, AI farms feed
	# their controller (same split every income source uses).
	if is_in_group("player_buildings"):
		GameState.add_salvage(TRICKLE_AMOUNT)
	elif owner_controller != null and is_instance_valid(owner_controller) and owner_controller.has_method("add_salvage"):
		owner_controller.add_salvage(TRICKLE_AMOUNT)
	# TELEMETRY: farm_trickle (cheap + frequent — log only if balance work needs it)


func _draw_building_icon() -> void:
	# Procedural-era icon: a sheaf — three pale stalks (replaced by sprite art).
	var col := Color(0.72, 0.66, 0.38)
	draw_line(Vector2(-5, 8), Vector2(-3, -8), col, 1.5)
	draw_line(Vector2(0, 8), Vector2(0, -10), col, 1.5)
	draw_line(Vector2(5, 8), Vector2(3, -8), col, 1.5)


func _get_skin_path() -> String:
	return "res://assets/buildings/farm.png"  # skin pass 2, 2026-06-11


func _get_faction_dressing() -> String:
	return "survivor"  # MapCraft C: spawn carries the faction identity
