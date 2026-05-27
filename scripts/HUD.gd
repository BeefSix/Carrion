extends CanvasLayer

@onready var _salvage_label: Label = $SalvagePanel/MarginContainer/SalvageLabel
@onready var _building_panel: PanelContainer = $BuildingPanel
@onready var _building_title: Label = $BuildingPanel/VBox/Title
@onready var _action_button: Button = $BuildingPanel/VBox/ActionButton
@onready var _status_label: Label = $BuildingPanel/VBox/StatusLabel

var _current_building = null


func _ready() -> void:
	GameState.salvage_changed.connect(_on_salvage_changed)
	_on_salvage_changed(GameState.salvage)
	_building_panel.hide()
	_status_label.visible = false
	_action_button.pressed.connect(_on_action_pressed)
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)


func _on_salvage_changed(value: int) -> void:
	_salvage_label.text = "Salvage: %d" % value


func _on_selection_changed(_units: Array, building) -> void:
	_current_building = building
	if building != null and is_instance_valid(building):
		_building_title.text = building.name
		_building_panel.show()
	else:
		_building_panel.hide()


func _on_action_pressed() -> void:
	if _current_building != null and is_instance_valid(_current_building):
		if _current_building.has_method("primary_action"):
			_current_building.primary_action()


func _process(_delta: float) -> void:
	if _current_building == null or not is_instance_valid(_current_building):
		return
	var has_action: bool = true
	if _current_building.has_method("has_action"):
		has_action = _current_building.has_action()
	if not has_action:
		_action_button.hide()
	else:
		_action_button.show()
		if _current_building.has_method("get_action_button_text"):
			_action_button.text = _current_building.get_action_button_text()
		if _current_building.has_method("get_action_available"):
			_action_button.disabled = not _current_building.get_action_available()
	if _current_building.has_method("get_status_text"):
		var status: String = _current_building.get_status_text()
		_status_label.text = status
		_status_label.visible = status != ""
	else:
		_status_label.visible = false
