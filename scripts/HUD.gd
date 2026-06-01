extends CanvasLayer

const MAX_ACTIONS := 5

const POP_REFRESH_INTERVAL := 0.5
const TOAST_LIFETIME := 3.5
const FACTION_COLORS := {
	GameState.Faction.MILITARY: Color("5a6644"),
	GameState.Faction.SURVIVOR: Color("7a5c3c"),
	GameState.Faction.TRIBAL: Color("8a6a3a"),
}

@onready var _salvage_label: Label = $SalvagePanel/MarginContainer/SalvageLabel
@onready var _actor_panel: PanelContainer = $BuildingPanel
@onready var _actor_title: Label = $BuildingPanel/VBox/Title
@onready var _status_label: Label = $BuildingPanel/VBox/StatusLabel
@onready var _speed_label: Label = $SpeedIndicator

@onready var _faction_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/FactionLabel
@onready var _pop_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/PopLabel
@onready var _eclipse_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/EclipseLabel
@onready var _squad_list: VBoxContainer = $SquadSidebar/VBox/SquadScroll/SquadList
@onready var _empty_hint: Label = $SquadSidebar/VBox/EmptyHint
@onready var _detail_separator: HSeparator = $SquadSidebar/VBox/DetailSeparator
@onready var _squad_detail: PanelContainer = $SquadSidebar/VBox/SquadDetail
@onready var _formation_option: OptionButton = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/FormationRow/FormationOption
@onready var _posture_option: OptionButton = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/PostureRow/PostureOption
@onready var _scatter_label: Label = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/ScatterLabel

var _pop_refresh_timer: float = 0.0

var _action_buttons: Array = []
var _current_actor = null
# Tracked separately from _current_actor because stance applies to the whole
# combat selection (not just single-actor BuildingPanel selections).
var _selected_combat_units: Array = []

var _selected_squad: Squad = null
var _toast_label: Label = null
var _toast_timer: float = 0.0

# Split state: per-member checkbox values for the currently-displayed detail squad.
# Rebuilt when the squad changes; queried when the Split button is pressed.
var _split_checks: Dictionary = {}  # Unit -> bool

# Disband confirmation dialog (built lazily).
var _confirm_dialog: ConfirmationDialog = null
var _pending_disband_id: int = -1

# Merge target picker (PopupMenu, built on demand).
var _merge_popup: PopupMenu = null
# Maps PopupMenu item index -> target squad id, for the currently-open merge.
var _merge_targets: Array = []


func _ready() -> void:
	add_to_group("hud")
	GameState.salvage_changed.connect(_on_salvage_changed)
	_on_salvage_changed(GameState.salvage)
	_actor_panel.hide()
	_status_label.visible = false
	_speed_label.visible = false
	_action_buttons = [
		$BuildingPanel/VBox/ActionButton,
		$BuildingPanel/VBox/ActionButton2,
		$BuildingPanel/VBox/ActionButton3,
		$BuildingPanel/VBox/ActionButton4,
		$BuildingPanel/VBox/ActionButton5,
	]
	for i in range(_action_buttons.size()):
		_action_buttons[i].pressed.connect(_on_action_pressed.bind(i))
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)
	_init_squad_sidebar()
	_init_toast()
	SquadManager.squad_created.connect(_on_squad_created)
	SquadManager.squad_disbanded.connect(_on_squad_disbanded)
	SquadManager.squad_updated.connect(_on_squad_updated)
	SquadManager.squad_membership_changed.connect(_on_squad_membership_changed)
	SquadManager.squad_leader_changed.connect(_on_squad_leader_changed)


func _init_toast() -> void:
	# Toast is a center-screen-bottom Label that fades out. Used for squad
	# validation errors and other transient notifications.
	_toast_label = Label.new()
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.anchor_top = 1.0
	_toast_label.anchor_bottom = 1.0
	_toast_label.offset_left = -300.0
	_toast_label.offset_right = 300.0
	_toast_label.offset_top = -100.0
	_toast_label.offset_bottom = -64.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.modulate = Color(1, 0.85, 0.7, 0)
	add_child(_toast_label)


func show_toast(msg: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = msg
	_toast_label.modulate = Color(1, 0.85, 0.7, 1)
	_toast_timer = TOAST_LIFETIME


func _init_squad_sidebar() -> void:
	# Faction header: name + accent color modulate so the player can see at a glance
	# which faction they're commanding. Pop count + Eclipse meter refresh in _process.
	var fkey: int = GameState.player_faction
	_faction_label.text = _faction_name(fkey)
	if FACTION_COLORS.has(fkey):
		_faction_label.modulate = FACTION_COLORS[fkey]
	_eclipse_label.text = "Eclipse: stable"  # placeholder until Eclipse system lands
	_squad_detail.hide()
	_detail_separator.hide()
	_refresh_pop_count()
	_refresh_empty_hint()
	# Populate formation + posture dropdowns. Items are added once; selection
	# is driven by the squad currently in the detail panel.
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


# ----- Squad signal handlers -----

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


# ----- Squad list rendering -----

func _add_squad_row(squad: Squad) -> void:
	var row := _build_squad_row(squad)
	row.name = "Squad_%d" % squad.id
	_squad_list.add_child(row)


func _remove_squad_row(squad_id: int) -> void:
	var node := _squad_list.get_node_or_null("Squad_%d" % squad_id)
	if node != null:
		node.queue_free()


func _refresh_squad_row(squad: Squad) -> void:
	var node := _squad_list.get_node_or_null("Squad_%d" % squad.id)
	if node == null:
		_add_squad_row(squad)
		return
	# Replace in place to keep ordering.
	var idx: int = node.get_index()
	node.queue_free()
	var row := _build_squad_row(squad)
	row.name = "Squad_%d" % squad.id
	_squad_list.add_child(row)
	_squad_list.move_child(row, idx)


func _build_squad_row(squad: Squad) -> Control:
	# One row = HBox: [name button (selects squad)] [rename btn] [count label] [disband btn]
	var hbox := HBoxContainer.new()
	var name_btn := Button.new()
	var name_text: String = squad.display_name
	if squad.is_scattering():
		name_text += " (scattered)"
	name_btn.text = name_text
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if squad.is_scattering():
		name_btn.modulate = Color(1, 0.7, 0.5)
	name_btn.pressed.connect(_on_squad_row_selected.bind(squad.id))
	hbox.add_child(name_btn)
	var rename_btn := Button.new()
	rename_btn.text = "R"
	rename_btn.tooltip_text = "Rename squad"
	rename_btn.custom_minimum_size = Vector2(24, 0)
	rename_btn.pressed.connect(_on_squad_row_rename.bind(squad.id))
	hbox.add_child(rename_btn)
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


func _on_squad_row_rename(squad_id: int) -> void:
	# Swap the row's name Button for an editable LineEdit. Enter confirms,
	# Esc / focus_exited reverts. Inline rename per the design doc.
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
	# Rebuild the row to restore the name button. Idempotent: refresh handles
	# the case where the row was already replaced by a submit.
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	_refresh_squad_row(squad)


func _on_squad_row_selected(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null and sel_mgr.has_method("select_squad"):
		sel_mgr.select_squad(squad)


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


# ----- Squad detail panel -----

func _render_squad_detail(squad: Squad) -> void:
	if squad == null:
		_hide_squad_detail()
		return
	var detail_title: Label = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailTitle
	var members_vbox: VBoxContainer = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailMembers
	detail_title.text = "%s  (%d/%d)" % [squad.display_name, squad.members.size(), squad.get_capacity()]
	# Wipe and re-render members. Reset split checks to match current membership
	# (any prior checks against removed units would be stale).
	for c in members_vbox.get_children():
		c.queue_free()
	_split_checks.clear()
	for u in squad.members:
		if not is_instance_valid(u):
			continue
		_split_checks[u] = false
		var row := _build_member_row(u, squad)
		members_vbox.add_child(row)
	_squad_detail.show()
	_detail_separator.show()
	_wire_detail_buttons(squad)
	_update_detail_buttons_state(squad)
	_sync_dropdowns(squad)
	_update_scatter_label(squad)


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


func _wire_detail_buttons(squad: Squad) -> void:
	# Connect split/merge once per render. Disconnect prior connections so the
	# bound squad id doesn't carry stale references after a re-render.
	var split_btn: Button = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/SplitButton
	var merge_btn: Button = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/MergeButton
	for c in split_btn.pressed.get_connections():
		split_btn.pressed.disconnect(c.callable)
	for c in merge_btn.pressed.get_connections():
		merge_btn.pressed.disconnect(c.callable)
	split_btn.pressed.connect(_on_split_pressed.bind(squad.id))
	merge_btn.pressed.connect(_on_merge_pressed.bind(squad.id))


func _update_detail_buttons_state(squad: Squad) -> void:
	var split_btn: Button = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/SplitButton
	var merge_btn: Button = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/MergeButton
	var checked_count: int = 0
	for v in _split_checks.values():
		if v:
			checked_count += 1
	# Split needs at least 2 checked AND at least 2 unchecked.
	var unchecked_count: int = _split_checks.size() - checked_count
	split_btn.disabled = not (checked_count >= 2 and unchecked_count >= 2)
	# Merge needs at least one other squad of same faction.
	var has_target: bool = false
	for s in SquadManager.get_all_squads():
		if s != squad and s.faction == squad.faction:
			has_target = true
			break
	merge_btn.disabled = not has_target


func _hide_squad_detail() -> void:
	_squad_detail.hide()
	_detail_separator.hide()


func _build_member_row(u, squad: Squad) -> Control:
	var hbox := HBoxContainer.new()
	# Checkbox marks unit for split. Toggling re-evaluates split-button enabled state.
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
		show_toast(result)


func _on_merge_pressed(squad_id: int) -> void:
	var squad := SquadManager.get_squad_by_id(squad_id)
	if squad == null:
		return
	# Build a PopupMenu listing same-faction squads (excluding self).
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
	var btn: Button = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailButtons/MergeButton
	_merge_popup.position = btn.global_position + Vector2(0, btn.size.y)
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
		show_toast(err)


func _on_salvage_changed(value: int) -> void:
	_salvage_label.text = "Salvage: %d" % value


func _on_selection_changed(units: Array, building) -> void:
	if building != null and is_instance_valid(building):
		_current_actor = building
		_actor_title.text = building.name
		_actor_panel.show()
	elif units.size() == 1 and is_instance_valid(units[0]) and _has_actions(units[0]):
		_current_actor = units[0]
		_actor_title.text = units[0].name
		_actor_panel.show()
	else:
		_current_actor = null
		_actor_panel.hide()

	# Combat units in the selection are still tracked for the X hotkey
	# (per-unit stance override; the squad posture dropdown is the primary UI).
	_selected_combat_units.clear()
	for u in units:
		if is_instance_valid(u) and u.is_in_group("combat_units"):
			_selected_combat_units.append(u)

	# Squad detail: show the squad of the first selected unit that has one.
	# If no selected unit is in a squad, the detail panel hides.
	_selected_squad = null
	for u in units:
		if is_instance_valid(u) and u.squad != null:
			_selected_squad = u.squad
			break
	if _selected_squad != null:
		_render_squad_detail(_selected_squad)
	else:
		_hide_squad_detail()


func _apply_stance_toggle() -> void:
	# X hotkey: cycle stance on selected combat units (per-unit override).
	# Sequence: AGGRESSIVE -> NEUTRAL -> PASSIVE -> AGGRESSIVE...
	# Squad posture is the primary control; this is the keyboard escape hatch.
	if _selected_combat_units.is_empty():
		return
	var first = _selected_combat_units[0]
	if not is_instance_valid(first):
		return
	var target_stance: int
	match first.stance:
		Unit.Stance.AGGRESSIVE: target_stance = Unit.Stance.NEUTRAL
		Unit.Stance.NEUTRAL: target_stance = Unit.Stance.PASSIVE
		_: target_stance = Unit.Stance.AGGRESSIVE
	for u in _selected_combat_units:
		if is_instance_valid(u):
			u.set_stance(target_stance)
	show_toast("Stance: " + _stance_name(target_stance))


func _stance_name(s: int) -> String:
	match s:
		Unit.Stance.AGGRESSIVE: return "Aggressive"
		Unit.Stance.NEUTRAL: return "Neutral"
		Unit.Stance.PASSIVE: return "Passive"
		_: return "?"


func _has_actions(actor) -> bool:
	if actor.has_method("get_action_count"):
		return actor.get_action_count() > 0
	return false


func _on_action_pressed(index: int) -> void:
	if _current_actor != null and is_instance_valid(_current_actor):
		if _current_actor.has_method("do_action"):
			_current_actor.do_action(index)


func _process(delta: float) -> void:
	if is_equal_approx(Engine.time_scale, 1.0):
		_speed_label.visible = false
	else:
		_speed_label.visible = true
		_speed_label.text = "Speed: %.0fx" % Engine.time_scale

	_pop_refresh_timer -= delta
	if _pop_refresh_timer <= 0.0:
		_pop_refresh_timer = POP_REFRESH_INTERVAL
		_refresh_pop_count()

	# Live scatter countdown for the displayed squad. Cheap update of one
	# label - we don't re-render the full detail panel.
	if _selected_squad != null and _selected_squad.is_scattering():
		_update_scatter_label(_selected_squad)

	# Toast fade-out.
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.modulate.a = 0.0
		elif _toast_timer < 1.0:
			_toast_label.modulate.a = _toast_timer  # last second fades

	if _current_actor == null or not is_instance_valid(_current_actor):
		return

	var count: int = 0
	if _current_actor.has_method("get_action_count"):
		count = _current_actor.get_action_count()

	for i in range(_action_buttons.size()):
		var btn: Button = _action_buttons[i]
		if i < count:
			btn.visible = true
			btn.text = _current_actor.get_action_text(i)
			btn.disabled = not _current_actor.get_action_available(i)
		else:
			btn.visible = false

	if _current_actor.has_method("get_status_text"):
		var status: String = _current_actor.get_status_text()
		_status_label.text = status
		_status_label.visible = status != ""
	else:
		_status_label.visible = false
