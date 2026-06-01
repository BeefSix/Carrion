extends PanelContainer

# Owns the sidebar UI: faction header, squad list, detail panel, scatter
# polling. Subscribes to SquadManager signals (squad lifecycle) and to
# SelectionManager.selection_changed (drives which squad's detail is shown).
# HUD.gd hosts the toast widget; this script calls show_toast on it via
# group lookup.
#
# Extracted from HUD.gd in the post-Phase-4 cleanup. Future split candidates:
# SquadRow widget (update-in-place row), SquadDetailPanel widget.

const POP_REFRESH_INTERVAL := 0.5
const FACTION_COLORS := {
	GameState.Faction.MILITARY: Color("5a6644"),
	GameState.Faction.SURVIVOR: Color("7a5c3c"),
	GameState.Faction.TRIBAL: Color("8a6a3a"),
}

@onready var _faction_label: Label = $VBox/FactionHeader/FactionMargin/FactionVBox/FactionLabel
@onready var _pop_label: Label = $VBox/FactionHeader/FactionMargin/FactionVBox/PopLabel
@onready var _eclipse_label: Label = $VBox/FactionHeader/FactionMargin/FactionVBox/EclipseLabel
@onready var _squad_list: VBoxContainer = $VBox/SquadScroll/SquadList
@onready var _empty_hint: Label = $VBox/EmptyHint
@onready var _detail_separator: HSeparator = $VBox/DetailSeparator
@onready var _squad_detail: PanelContainer = $VBox/SquadDetail
@onready var _detail_title: Label = $VBox/SquadDetail/DetailMargin/DetailVBox/DetailTitle
@onready var _detail_members: VBoxContainer = $VBox/SquadDetail/DetailMargin/DetailVBox/DetailMembers
@onready var _split_btn: Button = $VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/SplitButton
@onready var _merge_btn: Button = $VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/MergeButton
@onready var _formation_option: OptionButton = $VBox/SquadDetail/DetailMargin/DetailVBox/FormationRow/FormationOption
@onready var _posture_option: OptionButton = $VBox/SquadDetail/DetailMargin/DetailVBox/PostureRow/PostureOption
@onready var _scatter_label: Label = $VBox/SquadDetail/DetailMargin/DetailVBox/ScatterLabel

var _selected_squad: Squad = null
var _pop_refresh_timer: float = 0.0

# Split checkbox state for the currently-displayed squad. Reset on detail re-render.
var _split_checks: Dictionary = {}  # Unit -> bool

# Disband confirmation dialog (lazy).
var _confirm_dialog: ConfirmationDialog = null
var _pending_disband_id: int = -1

# Merge target picker (lazy).
var _merge_popup: PopupMenu = null
var _merge_targets: Array = []


func _ready() -> void:
	_init_faction_header()
	_init_dropdowns()
	_squad_detail.hide()
	_detail_separator.hide()
	_refresh_empty_hint()
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)
	SquadManager.squad_created.connect(_on_squad_created)
	SquadManager.squad_disbanded.connect(_on_squad_disbanded)
	SquadManager.squad_updated.connect(_on_squad_updated)
	SquadManager.squad_membership_changed.connect(_on_squad_membership_changed)
	SquadManager.squad_leader_changed.connect(_on_squad_leader_changed)


func _process(delta: float) -> void:
	_pop_refresh_timer -= delta
	if _pop_refresh_timer <= 0.0:
		_pop_refresh_timer = POP_REFRESH_INTERVAL
		_refresh_pop_count()
	# Live scatter countdown on the displayed squad. Cheap one-label update -
	# we don't re-render the full detail panel.
	if _selected_squad != null and _selected_squad.is_scattering():
		_update_scatter_label(_selected_squad)


# ----- Init -----

func _init_faction_header() -> void:
	var fkey: int = GameState.player_faction
	_faction_label.text = _faction_name(fkey)
	if FACTION_COLORS.has(fkey):
		_faction_label.modulate = FACTION_COLORS[fkey]
	_eclipse_label.text = "Eclipse: stable"  # placeholder until Eclipse system lands
	_refresh_pop_count()


func _init_dropdowns() -> void:
	_formation_option.clear()
	_formation_option.add_item("Standard", Squad.Formation.STANDARD)
	_formation_option.add_item("Line", Squad.Formation.LINE)
	_formation_option.add_item("Wedge", Squad.Formation.WEDGE)
	_formation_option.add_item("Column", Squad.Formation.COLUMN)
	_formation_option.add_item("Scattered", Squad.Formation.SCATTERED)
	_formation_option.item_selected.connect(_on_formation_changed)
	_posture_option.clear()
	_posture_option.add_item("Standard", Squad.Posture.STANDARD)
	_posture_option.add_item("Aggressive", Squad.Posture.AGGRESSIVE)
	_posture_option.add_item("Defensive", Squad.Posture.DEFENSIVE)
	_posture_option.item_selected.connect(_on_posture_changed)


# ----- Faction header -----

func _faction_name(f: int) -> String:
	match f:
		GameState.Faction.MILITARY: return "Military"
		GameState.Faction.SURVIVOR: return "Survivor"
		GameState.Faction.TRIBAL: return "Tribal"
		_: return "Unknown"


func _refresh_pop_count() -> void:
	var n: int = get_tree().get_nodes_in_group("player_units").size()
	_pop_label.text = "Units: %d" % n


func _refresh_empty_hint() -> void:
	var has_squads: bool = SquadManager.get_all_squads().size() > 0
	_empty_hint.visible = not has_squads


# ----- SquadManager signal handlers -----

func _on_squad_created(squad: Squad) -> void:
	_add_squad_row(squad)
	_refresh_empty_hint()


func _on_squad_disbanded(squad: Squad) -> void:
	_remove_squad_row(squad.id)
	if _selected_squad == squad:
		_selected_squad = null
		_hide_squad_detail()
	_refresh_empty_hint()


func _on_squad_updated(squad: Squad) -> void:
	_refresh_squad_row(squad)
	if _selected_squad == squad:
		_render_squad_detail(squad)


func _on_squad_membership_changed(squad: Squad) -> void:
	_refresh_squad_row(squad)
	if _selected_squad == squad:
		_render_squad_detail(squad)


func _on_squad_leader_changed(squad: Squad) -> void:
	_refresh_squad_row(squad)
	if _selected_squad == squad:
		_render_squad_detail(squad)


# ----- Selection integration -----

func _on_selection_changed(units: Array, _building) -> void:
	# Squad detail tracks the squad of the first selected unit that has one.
	_selected_squad = null
	for u in units:
		if is_instance_valid(u) and u.squad != null:
			_selected_squad = u.squad
			break
	if _selected_squad != null:
		_render_squad_detail(_selected_squad)
	else:
		_hide_squad_detail()


# ----- Squad list rendering -----

func _add_squad_row(squad: Squad) -> void:
	var row := _build_squad_row(squad)
	row.name = "Squad_%d" % squad.id
	_squad_list.add_child(row)


func _remove_squad_row(squad_id: int) -> void:
	var node := _squad_list.get_node_or_null("Squad_%d" % squad_id)
	if node != null:
		_squad_list.remove_child(node)
		node.queue_free()


func _refresh_squad_row(squad: Squad) -> void:
	var node := _squad_list.get_node_or_null("Squad_%d" % squad.id)
	if node == null:
		_add_squad_row(squad)
		return
	# remove_child is immediate; queue_free is deferred. Without this order,
	# the new row collides on the canonical name and Godot auto-renames it,
	# accumulating ghost rows on every refresh.
	var idx: int = node.get_index()
	_squad_list.remove_child(node)
	node.queue_free()
	var row := _build_squad_row(squad)
	row.name = "Squad_%d" % squad.id
	_squad_list.add_child(row)
	_squad_list.move_child(row, idx)


func _build_squad_row(squad: Squad) -> Control:
	# Row layout: [name button] [count label] [disband btn]
	# Name button interactions:
	#   left click          -> select squad members on the map
	#   left double-click   -> select + center camera on squad centroid
	#   right click         -> swap to inline LineEdit for rename
	var hbox := HBoxContainer.new()
	var name_btn := Button.new()
	var name_text: String = squad.display_name
	if squad.is_scattering():
		name_text += " (scattered)"
	name_btn.text = name_text
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.tooltip_text = "Click: select  •  Double-click: focus camera  •  Right-click: rename"
	if squad.is_scattering():
		name_btn.modulate = Color(1, 0.7, 0.5)
	name_btn.pressed.connect(_on_squad_row_selected.bind(squad.id))
	name_btn.gui_input.connect(_on_squad_name_gui_input.bind(squad.id))
	hbox.add_child(name_btn)
	var count_label := Label.new()
	count_label.text = "%d/%d" % [squad.members.size(), squad.get_capacity()]
	count_label.custom_minimum_size = Vector2(36, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(count_label)
	var disband_btn := Button.new()
	disband_btn.text = "X"
	disband_btn.tooltip_text = "Disband squad"
	disband_btn.custom_minimum_size = Vector2(28, 0)
	disband_btn.pressed.connect(_on_squad_row_disband.bind(squad.id))
	hbox.add_child(disband_btn)
	return hbox


# ----- Row interactions -----

func _on_squad_row_selected(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null and sel_mgr.has_method("select_squad"):
		sel_mgr.select_squad(squad)


func _on_squad_name_gui_input(event: InputEvent, squad_id: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_start_inline_rename(squad_id)
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		# Single click already routed via pressed signal -> select. Double-click
		# adds the camera focus on top. Selection stays valid through both.
		_focus_camera_on_squad(squad_id)


func _focus_camera_on_squad(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	var sum := Vector2.ZERO
	var n: int = 0
	for u in squad.members:
		if is_instance_valid(u):
			sum += u.global_position
			n += 1
	if n == 0:
		return
	var centroid: Vector2 = sum / float(n)
	var cam := get_tree().get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("center_on_world"):
		cam.center_on_world(centroid)


func _start_inline_rename(squad_id: int) -> void:
	# Swap the row's name Button for an editable LineEdit. Enter confirms,
	# focus-exit cancels.
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	var row := _squad_list.get_node_or_null("Squad_%d" % squad_id)
	if row == null:
		return
	var name_btn = row.get_child(0)
	if not (name_btn is Button):
		return
	var line_edit := LineEdit.new()
	line_edit.text = squad.display_name
	line_edit.max_length = 24
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text_submitted.connect(_on_rename_submitted.bind(squad_id))
	line_edit.focus_exited.connect(_on_rename_cancelled.bind(squad_id))
	row.remove_child(name_btn)
	name_btn.queue_free()
	row.add_child(line_edit)
	row.move_child(line_edit, 0)
	line_edit.grab_focus()
	line_edit.select_all()


func _on_rename_submitted(new_text: String, squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	SquadManager.rename_squad(squad, new_text)
	# squad_updated signal rebuilds the row.


func _on_rename_cancelled(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	_refresh_squad_row(squad)


func _on_squad_row_disband(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	if _confirm_dialog == null:
		_confirm_dialog = ConfirmationDialog.new()
		_confirm_dialog.title = "Disband Squad"
		_confirm_dialog.confirmed.connect(_on_disband_confirmed)
		add_child(_confirm_dialog)
	_pending_disband_id = squad_id
	_confirm_dialog.dialog_text = "Disband %s? Members will return to ungrouped state." % squad.display_name
	_confirm_dialog.popup_centered()


func _on_disband_confirmed() -> void:
	var squad := SquadManager.get_squad_by_id(_pending_disband_id)
	_pending_disband_id = -1
	if squad == null:
		return
	SquadManager.disband_squad(squad)


# ----- Detail panel -----

func _render_squad_detail(squad: Squad) -> void:
	if squad == null:
		_hide_squad_detail()
		return
	_detail_title.text = "%s  (%d/%d)" % [squad.display_name, squad.members.size(), squad.get_capacity()]
	# Wipe member rows. Immediate remove_child + queue_free for consistency
	# with the row-list pattern (avoids any deferred-tree quirks).
	for c in _detail_members.get_children():
		_detail_members.remove_child(c)
		c.queue_free()
	_split_checks.clear()
	for u in squad.members:
		if not is_instance_valid(u):
			continue
		_split_checks[u] = false
		var row := _build_member_row(u, squad)
		_detail_members.add_child(row)
	_squad_detail.show()
	_detail_separator.show()
	_wire_detail_buttons(squad)
	_update_detail_buttons_state(squad)
	_sync_dropdowns(squad)
	_update_scatter_label(squad)


func _hide_squad_detail() -> void:
	_squad_detail.hide()
	_detail_separator.hide()


func _build_member_row(u, squad: Squad) -> Control:
	var hbox := HBoxContainer.new()
	var check := CheckBox.new()
	check.button_pressed = _split_checks.get(u, false)
	check.toggled.connect(_on_member_check_toggled.bind(u, squad))
	hbox.add_child(check)
	var name_label := Label.new()
	var leader_marker: String = "* " if u == squad.leader else "  "
	name_label.text = "%s%s (%s)" % [leader_marker, u.name, Squad.rank_name(u.veterancy_level)]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if u == squad.leader:
		name_label.modulate = Color(1.0, 0.95, 0.7)
	hbox.add_child(name_label)
	var hp_label := Label.new()
	hp_label.text = "HP %d/%d" % [u.current_hp, u.get_effective_max_hp()]
	hp_label.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(hp_label)
	return hbox


func _on_member_check_toggled(checked: bool, u, squad: Squad) -> void:
	_split_checks[u] = checked
	_update_detail_buttons_state(squad)


func _wire_detail_buttons(squad: Squad) -> void:
	# Disconnect any prior bindings so the bound squad id doesn't carry stale
	# references after a re-render. Cheap.
	for c in _split_btn.pressed.get_connections():
		_split_btn.pressed.disconnect(c.callable)
	for c in _merge_btn.pressed.get_connections():
		_merge_btn.pressed.disconnect(c.callable)
	_split_btn.pressed.connect(_on_split_pressed.bind(squad.id))
	_merge_btn.pressed.connect(_on_merge_pressed.bind(squad.id))


func _update_detail_buttons_state(squad: Squad) -> void:
	var checked_count: int = 0
	for v in _split_checks.values():
		if v:
			checked_count += 1
	var unchecked_count: int = _split_checks.size() - checked_count
	# Split needs >=2 checked AND >=2 unchecked so both halves can survive validation.
	_split_btn.disabled = not (checked_count >= 2 and unchecked_count >= 2)
	# Merge needs at least one other same-faction squad to target.
	var has_target: bool = false
	for s in SquadManager.get_all_squads():
		if s != squad and s.faction == squad.faction:
			has_target = true
			break
	_merge_btn.disabled = not has_target


func _sync_dropdowns(squad: Squad) -> void:
	# Reflect the squad's current formation/posture in the dropdowns without
	# re-firing item_selected (which would re-write the value).
	for i in range(_formation_option.item_count):
		if _formation_option.get_item_id(i) == squad.formation:
			_formation_option.selected = i
			break
	for i in range(_posture_option.item_count):
		if _posture_option.get_item_id(i) == squad.posture:
			_posture_option.selected = i
			break


func _update_scatter_label(squad: Squad) -> void:
	if squad.is_scattering():
		_scatter_label.visible = true
		_scatter_label.text = "SCATTERED - reorganizing... %.0fs" % squad.scatter_timer
	else:
		_scatter_label.visible = false


func _on_formation_changed(idx: int) -> void:
	if _selected_squad == null:
		return
	var formation_id: int = _formation_option.get_item_id(idx)
	SquadManager.set_formation(_selected_squad, formation_id)


func _on_posture_changed(idx: int) -> void:
	if _selected_squad == null:
		return
	var posture_id: int = _posture_option.get_item_id(idx)
	SquadManager.set_posture(_selected_squad, posture_id)


# ----- Split + Merge -----

func _on_split_pressed(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	var to_move: Array = []
	for u in _split_checks.keys():
		if _split_checks[u] and is_instance_valid(u):
			to_move.append(u)
	var result = SquadManager.split_squad(squad, to_move)
	if result is String:
		_show_toast(result)


func _on_merge_pressed(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	if _merge_popup == null:
		_merge_popup = PopupMenu.new()
		_merge_popup.id_pressed.connect(_on_merge_target_picked)
		add_child(_merge_popup)
	_merge_popup.clear()
	_merge_targets.clear()
	for s in SquadManager.get_all_squads():
		if s == squad or s.faction != squad.faction:
			continue
		_merge_targets.append({"source_id": squad_id, "target_id": s.id})
		_merge_popup.add_item("Merge into %s" % s.display_name, _merge_targets.size() - 1)
	if _merge_popup.item_count == 0:
		return
	_merge_popup.position = _merge_btn.global_position + Vector2(0, _merge_btn.size.y)
	_merge_popup.popup()


func _on_merge_target_picked(idx: int) -> void:
	if idx < 0 or idx >= _merge_targets.size():
		return
	var pair = _merge_targets[idx]
	var source := SquadManager.get_squad_by_id(pair["source_id"])
	var target := SquadManager.get_squad_by_id(pair["target_id"])
	if source == null or target == null:
		return
	var err: String = SquadManager.merge_squads(target, source)
	if err != "":
		_show_toast(err)


# ----- Toast (delegated to HUD) -----

func _show_toast(msg: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(msg)
