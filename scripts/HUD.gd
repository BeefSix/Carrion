extends CanvasLayer

const MAX_ACTIONS := 5
const TOAST_LIFETIME := 3.5

@onready var _salvage_label: Label = $SalvagePanel/MarginContainer/SalvageLabel
@onready var _actor_panel: PanelContainer = $BuildingPanel
@onready var _actor_title: Label = $BuildingPanel/VBox/Title
@onready var _status_label: Label = $BuildingPanel/VBox/StatusLabel
@onready var _speed_label: Label = $SpeedIndicator

var _action_buttons: Array = []
var _current_actor = null
# Combat units in the current selection. Used by the X hotkey for the
# per-unit Stance cycle (AGGRESSIVE -> NEUTRAL -> PASSIVE). Squad posture
# is the primary control - this is the keyboard escape hatch for ungrouped
# combat units or per-unit overrides.
var _selected_combat_units: Array = []

var _toast_label: Label = null
var _toast_timer: float = 0.0


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
	_init_toast()


func _init_toast() -> void:
	# Toast is a center-screen-bottom Label that fades out. Used by
	# SquadSidebar (validation errors) and SelectionManager (squad form
	# failures). Lives on HUD so any subsystem can call show_toast.
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

	_selected_combat_units.clear()
	for u in units:
		if is_instance_valid(u) and u.is_in_group("combat_units"):
			_selected_combat_units.append(u)


func _apply_stance_toggle() -> void:
	# X hotkey: cycle stance on selected combat units.
	# Sequence: AGGRESSIVE -> NEUTRAL -> PASSIVE -> AGGRESSIVE...
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
