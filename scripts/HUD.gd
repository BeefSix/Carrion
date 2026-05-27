extends CanvasLayer

@onready var _salvage_label: Label = $SalvagePanel/MarginContainer/SalvageLabel
@onready var _actor_panel: PanelContainer = $BuildingPanel
@onready var _actor_title: Label = $BuildingPanel/VBox/Title
@onready var _action_button1: Button = $BuildingPanel/VBox/ActionButton
@onready var _action_button2: Button = $BuildingPanel/VBox/ActionButton2
@onready var _status_label: Label = $BuildingPanel/VBox/StatusLabel
@onready var _speed_label: Label = $SpeedIndicator

var _current_actor = null


func _ready() -> void:
	GameState.salvage_changed.connect(_on_salvage_changed)
	_on_salvage_changed(GameState.salvage)
	_actor_panel.hide()
	_status_label.visible = false
	_speed_label.visible = false
	_action_button1.pressed.connect(_on_action_pressed.bind(0))
	_action_button2.pressed.connect(_on_action_pressed.bind(1))
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)


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


func _has_actions(actor) -> bool:
	if actor.has_method("get_action_count"):
		return actor.get_action_count() > 0
	return false


func _on_action_pressed(index: int) -> void:
	if _current_actor != null and is_instance_valid(_current_actor):
		if _current_actor.has_method("do_action"):
			_current_actor.do_action(index)


func _process(_delta: float) -> void:
	if is_equal_approx(Engine.time_scale, 1.0):
		_speed_label.visible = false
	else:
		_speed_label.visible = true
		_speed_label.text = "Speed: %.0fx" % Engine.time_scale

	if _current_actor == null or not is_instance_valid(_current_actor):
		return

	var count: int = 0
	if _current_actor.has_method("get_action_count"):
		count = _current_actor.get_action_count()

	_action_button1.visible = count >= 1
	_action_button2.visible = count >= 2

	if count >= 1:
		_action_button1.text = _current_actor.get_action_text(0)
		_action_button1.disabled = not _current_actor.get_action_available(0)
	if count >= 2:
		_action_button2.text = _current_actor.get_action_text(1)
		_action_button2.disabled = not _current_actor.get_action_available(1)

	if _current_actor.has_method("get_status_text"):
		var status: String = _current_actor.get_status_text()
		_status_label.text = status
		_status_label.visible = status != ""
	else:
		_status_label.visible = false
