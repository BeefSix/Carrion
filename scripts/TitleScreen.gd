extends Control


func _ready() -> void:
	$VBox/MilitaryButton.pressed.connect(_on_military_pressed)
	$VBox/TribalButton.pressed.connect(_on_tribal_pressed)
	$VBox/SurvivorButton.pressed.connect(_on_survivor_pressed)


func _on_military_pressed() -> void:
	GameState.player_faction = GameState.Faction.MILITARY
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_tribal_pressed() -> void:
	GameState.player_faction = GameState.Faction.TRIBAL
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_survivor_pressed() -> void:
	GameState.player_faction = GameState.Faction.SURVIVOR
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
