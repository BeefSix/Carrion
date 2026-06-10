extends "res://scripts/Building.gd"

# Survivor Radio Station (DESIGN_MASTER §7.3, v1) — "radio stations attach
# to farms and control the economy." Broadcasts call civilians in; v1
# abstracts the civilian walk-in to a salvage grant per broadcast cycle,
# active ONLY while a friendly Farm stands within ATTACH_RADIUS (the
# pylon-attachment rule — a radio with no farm has nothing to feed
# arrivals with, so nobody stays).
#
# THE DIAL (the faction's Heavy Gunner decision, economic axis): louder
# broadcast = faster recruitment = more zombie attention. v1 ships a fixed
# quiet broadcast that still emits real NoiseBus noise — the economy is
# audible to the ecosystem from day one, just at the cautious end of the
# dial. The player-facing volume control is [PROPOSED] → connection pass.
#
# CONNECTED 2026-06-10 (Matt's go): the Builder places this via the
# BuildCatalog SURVIVOR table.

const ATTACH_RADIUS_PX := 320.0     # 10 tiles to a friendly farm
const BROADCAST_INTERVAL := 20.0    # sim seconds per cycle
const BROADCAST_INCOME := 15        # salvage per cycle — the real economy arm
# Quiet-end broadcast noise. NoiseField small-horde threshold is 150: one
# station stays under it; two stations broadcasting near each other merge
# emitters and WILL cross it. That overlap is intended — density of
# civilization draws the dead. Balance-lab placeholder.
const BROADCAST_NOISE := 60.0

var _broadcast_timer: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("radio_stations")


func _physics_process(delta: float) -> void:
	# Fixed-interval accumulator on the physics tick (Rule #2).
	_broadcast_timer += delta
	if _broadcast_timer >= BROADCAST_INTERVAL:
		_broadcast_timer -= BROADCAST_INTERVAL
		_broadcast()


func _attached_to_farm() -> bool:
	# Any same-team farm in radius. Boolean any-of — order-independent
	# (Rule #4 safe).
	var mine_player: bool = is_in_group("player_buildings")
	for f in get_tree().get_nodes_in_group("farms"):
		if not is_instance_valid(f):
			continue
		if mine_player != f.is_in_group("player_buildings"):
			continue
		if global_position.distance_to(f.global_position) <= ATTACH_RADIUS_PX:
			return true
	return false


func _broadcast() -> void:
	if not _attached_to_farm():
		return  # dead air: no farm, no arrivals, no noise worth making
	if is_in_group("player_buildings"):
		GameState.add_salvage(BROADCAST_INCOME)
	elif owner_controller != null and is_instance_valid(owner_controller) and owner_controller.has_method("add_salvage"):
		owner_controller.add_salvage(BROADCAST_INCOME)
	# The broadcast is HEARD. This emission is the faction's economic
	# noise signature (CLAUDE.md: profile changes are balance changes).
	NoiseBus.emit(global_position, BROADCAST_NOISE)
	MatchStats.log_event("radio_broadcast", {
		"x": global_position.x, "y": global_position.y,
		"income": BROADCAST_INCOME, "noise": BROADCAST_NOISE,
	})
	queue_redraw()


func get_status_text() -> String:
	if not _attached_to_farm():
		return "OFF AIR — needs a Farm within 10 tiles"
	return "Broadcasting (next cycle %ds)" % int(ceil(BROADCAST_INTERVAL - _broadcast_timer))


func _draw_building_icon() -> void:
	# Procedural-era icon: antenna mast with broadcast arcs.
	var col := Color(0.62, 0.66, 0.70)
	draw_line(Vector2(0, 10), Vector2(0, -12), col, 1.5)
	draw_line(Vector2(-4, 10), Vector2(0, 2), col, 1.0)
	draw_line(Vector2(4, 10), Vector2(0, 2), col, 1.0)
	if _attached_to_farm():
		draw_arc(Vector2(0, -12), 5.0, -2.2, -0.9, 6, col, 1.0)
		draw_arc(Vector2(0, -12), 8.0, -2.2, -0.9, 6, col, 1.0)


func _get_skin_path() -> String:
	return "res://assets/buildings/radio_station.png"  # skin pass 2, 2026-06-11
