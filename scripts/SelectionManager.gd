class_name SelectionManager
extends Node2D

signal selection_changed(units: Array, building)

const DRAG_THRESHOLD_PX := 8.0
const WALL_GRID := 32.0
const WALL_COST := 25
const RUBBLE_TILE := 2

var _dragging := false
var _drag_start_iso: Vector2
var _drag_start_screen: Vector2
var _selected_units: Array = []
var _selected_building = null

var _placing_wall := false
var _wall_builder = null

# SC-style building placement (2026-06-10): a worker's build action puts
# the manager in placement mode; the ghost follows the mouse with validity
# coloring; LMB pays + spawns a ConstructionSite + orders the worker to
# build it; RMB cancels.
const SITE_SCENE := preload("res://scenes/buildings/ConstructionSite.tscn")
const BuildCatalogRef := preload("res://scripts/BuildCatalog.gd")
var _placing_building := false
var _building_builder = null
var _building_key: String = ""
var _building_entry: Dictionary = {}


func _ready() -> void:
	add_to_group("selection_manager")


func start_building_placement(builder, key: String, entry: Dictionary) -> void:
	_placing_building = true
	_building_builder = builder
	_building_key = key
	_building_entry = entry
	queue_redraw()


func _cancel_building_placement() -> void:
	_placing_building = false
	_building_builder = null
	_building_key = ""
	_building_entry = {}
	queue_redraw()


func _confirm_building_placement(world_pos: Vector2) -> void:
	if _building_builder == null or not is_instance_valid(_building_builder) or not _building_builder.has_method("construct_at"):
		_cancel_building_placement()
		return
	var fp: Vector2 = _building_entry["footprint"]
	var snapped := _snap_to_grid(world_pos)
	if not _is_footprint_valid(snapped, fp):
		return  # keep placement mode active — pick another spot
	var cost: int = int(_building_entry["cost"])
	if not GameState.can_spend(cost):
		_cancel_building_placement()
		return
	GameState.spend(cost)
	# Spawn the scaffold NOW (blocks the spot, attackable — SC rule: sunk
	# cost, no refund) and send the worker to it via CommandBus.
	var site = SITE_SCENE.instantiate()
	site.setup(_building_key, _building_entry)
	site.position = snapped
	get_tree().current_scene.add_child(site)
	site.add_to_group("player_buildings")
	CommandBus.issue("construct", _building_builder, {"target": site}, CommandBus.SRC_PLAYER)
	_cancel_building_placement()


# Footprint validity: same checks as walls, sized to the building.
func _is_footprint_valid(center: Vector2, footprint: Vector2) -> bool:
	var ground := get_tree().get_first_node_in_group("ground_tiles")
	if ground != null and ground.has_method("get_tile_type_at"):
		# Probe center + the four footprint corners (cheap coverage).
		for off in [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var t: int = ground.get_tile_type_at(center + off * footprint)
			if t == -1 or t == RUBBLE_TILE:
				return false
	var rect := Rect2(center - footprint * 0.5, footprint)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if not ("size_pixels" in b):
			continue
		var brect := Rect2(b.position - b.size_pixels * 0.5, b.size_pixels)
		if rect.intersects(brect):
			return false
	return true


func start_wall_placement(builder) -> void:
	_placing_wall = true
	_wall_builder = builder
	queue_redraw()


func _cancel_wall_placement() -> void:
	_placing_wall = false
	_wall_builder = null
	queue_redraw()


func _confirm_wall_placement(world_pos: Vector2) -> void:
	if _wall_builder == null or not is_instance_valid(_wall_builder) or not _wall_builder.has_method("build_wall_at"):
		_cancel_wall_placement()
		return
	var snapped := _snap_to_grid(world_pos)
	if not _is_wall_placement_valid(snapped):
		return  # keep placement mode active so the player can pick another spot
	if not GameState.can_spend(WALL_COST):
		_cancel_wall_placement()
		return
	GameState.spend(WALL_COST)
	CommandBus.issue("build_wall", _wall_builder, {"target": snapped}, CommandBus.SRC_PLAYER)
	_cancel_wall_placement()


func _snap_to_grid(p: Vector2) -> Vector2:
	# Operates in world coords. Snaps to the 32-px world grid (which is the
	# wall placement grid). Iso projection is applied only at draw time so
	# the snapped world coord can also feed nav, physics, and gameplay checks.
	return (p / WALL_GRID).floor() * WALL_GRID + Vector2(WALL_GRID, WALL_GRID) * 0.5


func _is_wall_placement_valid(center: Vector2) -> bool:
	# All inputs and checks here are in world coords. Collision footprints
	# stay in world space; only rendering is iso-projected.
	var ground := get_tree().get_first_node_in_group("ground_tiles")
	if ground != null and ground.has_method("get_tile_type_at"):
		var t: int = ground.get_tile_type_at(center)
		if t == -1 or t == RUBBLE_TILE:
			return false
	var wall_rect := Rect2(center - Vector2(WALL_GRID, WALL_GRID) * 0.5, Vector2(WALL_GRID, WALL_GRID))
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if not ("size_pixels" in b):
			continue
		var bhalf: Vector2 = b.size_pixels * 0.5
		var brect := Rect2(b.position - bhalf, b.size_pixels)
		if wall_rect.intersects(brect):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	# Camera lives in iso screen-space (Phase 2), so get_global_mouse_position()
	# returns the iso position of the cursor. Gameplay (physics queries, nav,
	# collision shapes, building.position, unit.position) all stay in world
	# coords - so we project iso back to world at the boundary before passing
	# to handlers.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null and hud.has_method("_apply_stance_toggle"):
				hud._apply_stance_toggle()
			return
		if event.keycode == KEY_G:
			_form_squad_from_selection()
			return

	if _placing_wall:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_wall_placement(_mouse_world())
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_wall_placement()
		elif event is InputEventMouseMotion:
			queue_redraw()
		return

	if _placing_building:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_building_placement(_mouse_world())
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_building_placement()
		elif event is InputEventMouseMotion:
			queue_redraw()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start_screen = event.position
				_drag_start_iso = get_global_mouse_position()
				_dragging = true
			elif _dragging:
				# Pre-H8 this branch had no _dragging guard, so the LMB-release
				# that followed a consumed wall-placement press (or any other
				# UI press where _dragging was never set) finalized a phantom
				# selection with stale _drag_start_iso, typically clearing the
				# Engineer the user had selected.
				_finalize_selection(event.position, _drag_start_iso, get_global_mouse_position())
				_dragging = false
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(_mouse_world())
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()


func _mouse_world() -> Vector2:
	return IsoView.screen_to_world(get_global_mouse_position())


func _handle_right_click(world_pos: Vector2) -> void:
	var target_corpse = _find_corpse_at(world_pos)
	var target_remains = _find_remains_at(world_pos)
	var target_building = _find_building_at(world_pos)
	var target_lootable = null
	if target_building != null and target_building.is_in_group("lootable"):
		target_lootable = target_building
	var is_infested: bool = (target_lootable != null) and ("is_infested" in target_lootable) and target_lootable.is_infested
	var is_damaged: bool = (target_building != null) and ("current_hp" in target_building) and ("max_hp" in target_building) and target_building.current_hp < target_building.max_hp

	# H10: repair only targets player-owned buildings. Pre-fix a right-click on
	# a damaged enemy HQ routed Engineers to repair the enemy, which is absurd.
	# Computed once here so the count-pass and execute-pass use the same gate.
	var building_is_player_owned: bool = target_building != null and GameState.is_owned_by_player(target_building)

	# First pass: count how many units will receive a plain move command. They
	# get distributed formation targets so they don't converge on a single
	# point (which produces the "straying / teleporting back" pile-up).
	var move_unit_count: int = 0
	for u in _selected_units:
		if not is_instance_valid(u):
			continue
		var has_corpse_action: bool = target_corpse != null and u.is_in_group("combat_units")
		var has_repair_action: bool = target_building != null and is_damaged and building_is_player_owned and u.has_method("repair_at")
		var has_force_spawn_action: bool = target_lootable != null and is_infested and u.has_method("force_spawn_at")
		var has_gather_action: bool = target_lootable != null and u.has_method("gather_from")
		# B2: Caller ground clicks route to the whistle (which itself walks
		# when the point is out of whistle range) — never to plain move.
		var has_whistle_action: bool = target_building == null and target_corpse == null and u.has_method("whistle_at")
		# B3: Walker right-click on a remains pile = harvest order.
		var has_harvest_action: bool = target_remains != null and u.has_method("harvest_remains")
		if has_corpse_action or has_repair_action or has_force_spawn_action or has_gather_action or has_whistle_action or has_harvest_action:
			continue
		if u.has_method("move_to"):
			move_unit_count += 1

	var move_index: int = 0
	for u in _selected_units:
		if not is_instance_valid(u):
			continue
		# Cremation is highest priority when the click landed on a corpse and the
		# unit is a combat unit. cremate_target is inherited from Unit.gd by ALL
		# subclasses (including workers), so we must filter by group.
		if target_corpse != null and u.is_in_group("combat_units"):
			CommandBus.issue("cremate", u, {"target": target_corpse}, CommandBus.SRC_PLAYER)
		elif target_building != null and is_damaged and building_is_player_owned and u.has_method("repair_at"):
			CommandBus.issue("repair", u, {"target": target_building}, CommandBus.SRC_PLAYER)
		elif target_lootable != null and is_infested and u.has_method("force_spawn_at"):
			CommandBus.issue("force_spawn", u, {"target": target_lootable}, CommandBus.SRC_PLAYER)
		elif target_lootable != null and u.has_method("gather_from"):
			CommandBus.issue("gather", u, {"target": target_lootable}, CommandBus.SRC_PLAYER)
		elif target_remains != null and u.has_method("harvest_remains"):
			CommandBus.issue("harvest", u, {"target": target_remains}, CommandBus.SRC_PLAYER)
		elif target_building == null and target_corpse == null and u.has_method("whistle_at"):
			CommandBus.issue("whistle", u, {"target": world_pos}, CommandBus.SRC_PLAYER)
		elif u.has_method("move_to"):
			var per_unit_target: Vector2 = _formation_position(world_pos, move_index, move_unit_count)
			CommandBus.issue("move", u, {"target": per_unit_target}, CommandBus.SRC_PLAYER)
			move_index += 1


# Concentric-ring formation. 1 unit at center, 6 in first ring at FORMATION_SPACING,
# 12 in second ring at 2*spacing, 18 in third at 3*spacing, ...
# Each unit gets a distinct world target so they don't pile up at one point and
# the physics solver doesn't need to push overlapping bodies apart (which read
# as straying-then-teleporting-back).
#
# D6 (AUDIT 2026-06-09): formation targets are SIM STATE (they become nav
# targets), so the old cos/sin ring violated the no-transcendentals rule
# (CLAUDE.md #5 — sin/cos diverge across CPUs). Replaced with an exact
# integer hex-ring walk (redblobgames axial rings): ring r holds 6r slots,
# same capacity as before, and the axial->world conversion uses only
# +,*,/ and the literal constant sqrt(3)/2 — compile-time constants don't
# diverge, transcendental CALLS do. Visually a hexagon instead of a circle;
# at 6/12/18 slots the silhouettes are near-identical.
const FORMATION_SPACING := 32.0
const HEX_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const HEX_ROW_Y := 0.8660254  # sqrt(3)/2 as a literal — no runtime transcendental

func _formation_position(center: Vector2, index: int, total: int) -> Vector2:
	if total <= 1 or index == 0:
		return center
	# Find which ring this index lands in.
	var ring: int = 1
	var positions_before_ring: int = 1
	while index >= positions_before_ring + 6 * ring:
		positions_before_ring += 6 * ring
		ring += 1
	var ring_index: int = index - positions_before_ring
	# Hex ring walk: start at the corner in direction 4, then step along
	# the six edges. side = which edge, step = distance along it. Integer
	# axial coords throughout; exact and order-free.
	var side: int = ring_index / ring
	var step: int = ring_index % ring
	var axial: Vector2i = HEX_DIRS[4] * ring
	for s in range(side):
		axial += HEX_DIRS[s] * ring
	axial += HEX_DIRS[side] * step
	# Axial -> world: x = q + r/2, y = r * sqrt(3)/2.
	var offset := Vector2(float(axial.x) + float(axial.y) * 0.5, float(axial.y) * HEX_ROW_Y)
	return center + offset * FORMATION_SPACING


func _find_building_at(world_pos: Vector2):
	# world_pos is in world coords. Building collisions live in world coords too
	# (only their _draw shifts to iso). Physics query at the world position
	# finds the collider for whatever building visually sits there.
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_point(params)
	for hit in hits:
		var collider = hit.collider
		if collider != null and collider.is_in_group("buildings"):
			return collider
	return null


func _find_remains_at(world_pos: Vector2):
	# B3: same click model as corpses — nearest remains within a small
	# click radius.
	const REMAINS_CLICK_RADIUS := 14.0
	var nearest = null
	var nearest_d := REMAINS_CLICK_RADIUS
	for r in get_tree().get_nodes_in_group("remains"):
		if not is_instance_valid(r):
			continue
		var d: float = world_pos.distance_to(r.position)
		if d < nearest_d:
			nearest_d = d
			nearest = r
	return nearest


func _find_corpse_at(world_pos: Vector2):
	const CORPSE_CLICK_RADIUS := 14.0
	var nearest = null
	var nearest_d := CORPSE_CLICK_RADIUS
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		var d: float = world_pos.distance_to(c.global_position)
		if d <= nearest_d:
			nearest_d = d
			nearest = c
	return nearest


func _finalize_selection(end_screen: Vector2, start_iso: Vector2, end_iso: Vector2) -> void:
	var screen_distance := _drag_start_screen.distance_to(end_screen)
	if screen_distance < DRAG_THRESHOLD_PX:
		# Click - convert iso click to world for the physics query.
		_click_select(IsoView.screen_to_world(end_iso))
	else:
		# Drag - rect is in iso coords (matches the visual the user dragged).
		_box_select_iso(start_iso, end_iso)


func _click_select(world_pos: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hits := space.intersect_point(params)
	_clear_selection()
	for hit in hits:
		var collider = hit.collider
		if collider == null:
			continue
		# H10: only select buildings the player owns. Pre-fix the player could
		# select any building (including AI Barracks / Lootables) and HUD would
		# run their do_action with no ownership gate. Lootables count as player-
		# owned for gather/force-spawn flows (they're tagged into player_buildings
		# on spawn-claim and are neutral pickups otherwise).
		if collider.is_in_group("buildings") and GameState.is_owned_by_player(collider):
			_select_building(collider)
			_emit_change()
			return
		if collider.is_in_group("player_units"):
			_add_to_selection(collider)
			_emit_change()
			return
	_emit_change()


func _box_select_iso(corner_a_iso: Vector2, corner_b_iso: Vector2) -> void:
	# Rect is in iso screen space (matches what the user dragged). Each player
	# unit lives at world coords, so we project unit.position to iso before
	# checking containment.
	var rect := Rect2(corner_a_iso, corner_b_iso - corner_a_iso).abs()
	_clear_selection()
	for unit in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(unit):
			continue
		var unit_iso: Vector2 = IsoView.world_to_screen(unit.position)
		if rect.has_point(unit_iso):
			_add_to_selection(unit)
	_emit_change()


func _clear_selection() -> void:
	for u in _selected_units:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.set_selected(false)
	_selected_units.clear()
	if _selected_building != null and is_instance_valid(_selected_building):
		if _selected_building.has_method("set_selected"):
			_selected_building.set_selected(false)
	_selected_building = null


func _select_building(b) -> void:
	_selected_building = b
	if b.has_method("set_selected"):
		b.set_selected(true)


func _add_to_selection(u) -> void:
	if u not in _selected_units:
		_selected_units.append(u)
		if u.has_method("set_selected"):
			u.set_selected(true)
		# Pre-H7, dead units were never pruned - a freed-instance reference in
		# _selected_units crashed downstream consumers (e.g. SquadManager
		# create_squad reading units[0].faction). Listen for tree_exiting and
		# drop the unit before the reference goes stale. ONE_SHOT so the
		# connection cleans itself up; the handler is idempotent if the unit
		# is reselected before dying (a new ONE_SHOT replaces the previous).
		u.tree_exiting.connect(_on_selected_exiting.bind(u), CONNECT_ONE_SHOT)


func _on_selected_exiting(u) -> void:
	if u in _selected_units:
		_selected_units.erase(u)
		_emit_change()


func _emit_change() -> void:
	selection_changed.emit(_selected_units.duplicate(), _selected_building)


func get_selected() -> Array:
	return _selected_units.duplicate()


# Public: select all members of a squad. Used by the sidebar squad-row click.
# Camera does NOT auto-center per the design doc - the player chooses where to look.
func select_squad(squad: Squad) -> void:
	if squad == null:
		return
	_clear_selection()
	for u in squad.members:
		if is_instance_valid(u):
			_add_to_selection(u)
	_emit_change()


func _form_squad_from_selection() -> void:
	# G hotkey path. Routes through SquadManager which handles validation,
	# leader assignment, and naming. On validation failure, shows a HUD toast
	# instead of forming.
	if _selected_units.is_empty():
		return
	var faction: int = _player_faction_value()
	var result = SquadManager.create_squad(_selected_units.duplicate(), faction)
	if result is String:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast(result)
		return
	# Successful creation - the sidebar will update via SquadManager signals.
	# Keep current selection (the newly-squaded units are still selected, which
	# triggers the detail panel for the new squad).
	_emit_change()


func _player_faction_value() -> int:
	# Faction is unified as GameState.Faction (consolidated 2026-06). Squad
	# faction reads from a representative selected unit.
	for u in _selected_units:
		if is_instance_valid(u):
			return u.faction
	return -1


func _draw() -> void:
	if _placing_wall:
		# Snap in world, project the snapped position to iso for the visual.
		# Type annotations explicit because IsoView returns untyped Variant
		# (autoload had to drop typed return signatures to register cleanly).
		var snapped_world: Vector2 = _snap_to_grid(_mouse_world())
		var iso_center: Vector2 = IsoView.world_to_screen(snapped_world)
		var half := Vector2(WALL_GRID, WALL_GRID) * 0.5
		var valid: bool = _is_wall_placement_valid(snapped_world) and GameState.can_spend(WALL_COST)
		var fill: Color = Color(0.4, 0.8, 0.4, 0.35) if valid else Color(0.9, 0.35, 0.3, 0.35)
		var border: Color = Color(0.6, 1.0, 0.6, 0.85) if valid else Color(1.0, 0.45, 0.4, 0.85)
		draw_rect(Rect2(iso_center - half, Vector2(WALL_GRID, WALL_GRID)), fill, true)
		draw_rect(Rect2(iso_center - half, Vector2(WALL_GRID, WALL_GRID)), border, false, 2.0)
	if _placing_building:
		var snapped_b: Vector2 = _snap_to_grid(_mouse_world())
		var iso_c: Vector2 = IsoView.world_to_screen(snapped_b)
		var fp: Vector2 = _building_entry["footprint"]
		var ok: bool = _is_footprint_valid(snapped_b, fp) and GameState.can_spend(int(_building_entry["cost"]))
		var fill_b: Color = Color(0.4, 0.8, 0.4, 0.3) if ok else Color(0.9, 0.35, 0.3, 0.3)
		var border_b: Color = Color(0.6, 1.0, 0.6, 0.85) if ok else Color(1.0, 0.45, 0.4, 0.85)
		draw_rect(Rect2(iso_c - fp * 0.5, fp), fill_b, true)
		draw_rect(Rect2(iso_c - fp * 0.5, fp), border_b, false, 2.0)
	if _dragging:
		# Drag rect is purely iso - it matches the screen-space box the user
		# is sweeping across the visible game.
		var current_iso: Vector2 = get_global_mouse_position()
		var rect := Rect2(_drag_start_iso, current_iso - _drag_start_iso).abs()
		draw_rect(rect, Color(1, 1, 0.4, 0.18), true)
		draw_rect(rect, Color(1, 1, 0.4, 0.7), false, 2.0)
