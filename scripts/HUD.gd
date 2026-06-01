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
@onready var _stance_panel: PanelContainer = $StancePanel
@onready var _stance_label: Label = $StancePanel/HBox/StanceLabel
@onready var _stance_button: Button = $StancePanel/HBox/StanceButton

@onready var _faction_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/FactionLabel
@onready var _pop_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/PopLabel
@onready var _eclipse_label: Label = $SquadSidebar/VBox/FactionHeader/FactionMargin/FactionVBox/EclipseLabel
@onready var _squad_list: VBoxContainer = $SquadSidebar/VBox/SquadScroll/SquadList
@onready var _empty_hint: Label = $SquadSidebar/VBox/EmptyHint
@onready var _detail_separator: HSeparator = $SquadSidebar/VBox/DetailSeparator
@onready var _squad_detail: PanelContainer = $SquadSidebar/VBox/SquadDetail

var _pop_refresh_timer: float = 0.0

var _action_buttons: Array = []
var _current_actor = null
# Tracked separately from _current_actor because stance applies to the whole
# combat selection (not just single-actor BuildingPanel selections).
var _selected_combat_units: Array = []

var _selected_squad: Squad = null
var _toast_label: Label = null
var _toast_timer: float = 0.0


func _ready() -> void:
	add_to_group("hud")
	GameState.salvage_changed.connect(_on_salvage_changed)
	_on_salvage_changed(GameState.salvage)
	_actor_panel.hide()
	_status_label.visible = false
	_speed_label.visible = false
	_stance_panel.hide()
	_stance_button.pressed.connect(_on_stance_button_pressed)
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
	# Squad list is empty in Phase 1; the hint will hide automatically when squads
	# exist (Phase 2 onward). For now it shows the form-squad prompt.
	_refresh_empty_hint()


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
	# One row = HBox with [name button (selects squad)] [count label] [disband btn]
	# Phase 3 will add Focus + Rename icons.
	var hbox := HBoxContainer.new()
	var name_btn := Button.new()
	name_btn.text = squad.display_name
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_on_squad_row_selected.bind(squad.id))
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
	# Phase 3 adds a confirmation prompt. Phase 2 just disbands directly.
	SquadManager.disband_squad(squad)


# ----- Squad detail panel -----

func _render_squad_detail(squad: Squad) -> void:
	if squad == null:
		_hide_squad_detail()
		return
	var detail_title: Label = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailTitle
	var members_vbox: VBoxContainer = $SquadSidebar/VBox/SquadDetail/DetailMargin/DetailVBox/DetailMembers
	detail_title.text = "%s  (%d/%d)" % [squad.display_name, squad.members.size(), squad.get_capacity()]
	# Wipe and re-render members.
	for c in members_vbox.get_children():
		c.queue_free()
	for u in squad.members:
		if not is_instance_valid(u):
			continue
		var row := _build_member_row(u, squad)
		members_vbox.add_child(row)
	_squad_detail.show()
	_detail_separator.show()


func _hide_squad_detail() -> void:
	_squad_detail.hide()
	_detail_separator.hide()


func _build_member_row(u, squad: Squad) -> Control:
	var hbox := HBoxContainer.new()
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

	# Stance panel applies to combat units in the selection. Hidden when the
	# selection contains no combat units.
	_selected_combat_units.clear()
	for u in units:
		if is_instance_valid(u) and u.is_in_group("combat_units"):
			_selected_combat_units.append(u)
	if _selected_combat_units.is_empty():
		_stance_panel.hide()
	else:
		_stance_panel.show()
		_refresh_stance_label()

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


func _refresh_stance_label() -> void:
	# Mixed-stance selection reads as whatever the first combat unit shows; the
	# toggle then flips everyone to the opposite. Cheap to recompute per click.
	if _selected_combat_units.is_empty():
		return
	var first = _selected_combat_units[0]
	if not is_instance_valid(first):
		return
	var s: int = first.stance
	_stance_label.text = "Stance: Aggressive" if s == Unit.Stance.AGGRESSIVE else "Stance: Passive"


func _on_stance_button_pressed() -> void:
	_apply_stance_toggle()


func _apply_stance_toggle() -> void:
	# Flip every combat unit in the current selection to the opposite of the
	# first unit's stance. Called from the button and from the X hotkey
	# (SelectionManager._unhandled_input).
	if _selected_combat_units.is_empty():
		return
	var first = _selected_combat_units[0]
	if not is_instance_valid(first):
		return
	var target_stance: int = Unit.Stance.PASSIVE if first.stance == Unit.Stance.AGGRESSIVE else Unit.Stance.AGGRESSIVE
	for u in _selected_combat_units:
		if is_instance_valid(u):
			u.set_stance(target_stance)
	_refresh_stance_label()


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
