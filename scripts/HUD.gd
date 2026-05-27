extends CanvasLayer

@onready var _salvage_label: Label = $SalvagePanel/MarginContainer/SalvageLabel


func _ready() -> void:
	GameState.salvage_changed.connect(_on_salvage_changed)
	_on_salvage_changed(GameState.salvage)


func _on_salvage_changed(value: int) -> void:
	_salvage_label.text = "Salvage: %d" % value
