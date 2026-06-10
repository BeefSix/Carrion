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


# SC-console era (2026-06-10): the bottom console (minimap + selection +
# command card) supersedes the old BuildingPanel/SalvagePanel. Those scene
# nodes stay hidden (scene surgery deferred); HUD keeps the toast, the
# stance hotkey, and the speed indicator, and hosts the new console +
# resource bar built in code.
var _console: Control = null
var _resource_label: Label = null


func _ready() -> void:
	add_to_group("hud")
	GameState.salvage_changed.connect(_on_salvage_changed)
	_actor_panel.hide()
	$SalvagePanel.hide()
	_status_label.visible = false
	_speed_label.visible = false
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)
	_init_toast()
	_console = preload("res://scripts/ui/Console.gd").new()
	add_child(_console)
	_build_resource_bar()
	_on_salvage_changed(GameState.salvage)


func _build_resource_bar() -> void:
	# Top-right resource readout (SC position), styled to match the console.
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -200.0
	panel.offset_right = -12.0
	panel.offset_top = 10.0
	panel.offset_bottom = 44.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.09, 0.095, 0.97)
	sb.border_color = Color(0.30, 0.29, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	_resource_label = Label.new()
	_resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_resource_label.add_theme_color_override("font_color", Color(0.85, 0.83, 0.76))
	_resource_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_resource_label)
	add_child(panel)


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
	if _resource_label != null:
		_resource_label.text = "SALVAGE  %d" % value


func _on_selection_changed(units: Array, building) -> void:
	# H10: only adopt buildings the player owns as the action actor.
	# SelectionManager already gates click-select, but signal payloads can in
	# principle carry enemy buildings (e.g. future hover-preview), so the gate
	# lives here too for defense in depth.
	if building != null and is_instance_valid(building) and GameState.is_owned_by_player(building):
		_current_actor = building
	elif units.size() == 1 and is_instance_valid(units[0]) and _has_actions(units[0]):
		_current_actor = units[0]
	else:
		_current_actor = null

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
		# H10 defense-in-depth: even if a non-owned building somehow became the
		# actor, never let its do_action fire. Buildings cleared by the
		# ownership gate; non-buildings (selected units) pass through.
		if _current_actor is Building and not GameState.is_owned_by_player(_current_actor):
			return
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

	# (Old BuildingPanel refresh removed — the Console owns the command
	# card and status line now. _current_actor is kept for the stance
	# hotkey bookkeeping in _on_selection_changed.)
