extends CanvasLayer

const MAX_ACTIONS := 5

const POP_REFRESH_INTERVAL := 0.5
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
	# Phase 1: no squads exist yet, so the hint is always visible. Phase 2 will
	# toggle this based on the actual squad list.
	var has_squads: bool = _squad_list.get_child_count() > 0
	_empty_hint.visible = not has_squads


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
