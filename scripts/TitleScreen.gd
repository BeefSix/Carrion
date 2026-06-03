extends Control


func _ready() -> void:
	$VBox/MilitaryButton.pressed.connect(_on_military_pressed)
	$VBox/TribalButton.pressed.connect(_on_tribal_pressed)
	$VBox/SurvivorButton.pressed.connect(_on_survivor_pressed)


func _on_military_pressed() -> void:
	_start(GameState.Faction.MILITARY)


func _on_tribal_pressed() -> void:
	_start(GameState.Faction.TRIBAL)


func _on_survivor_pressed() -> void:
	_start(GameState.Faction.SURVIVOR)


func _start(faction: int) -> void:
	GameState.player_faction = faction
	GameState.ai_enabled = $VBox/AICheck.button_pressed
	# Image-to-map PoC: when checked, Main.gd loads the Ridley JSON
	# instead of running TownPlanner procedurally.
	if has_node("VBox/RidleyCheck") and $VBox/RidleyCheck.button_pressed:
		GameState.custom_map_path = "res://assets/maps/ridley_data.json"
	else:
		GameState.custom_map_path = ""
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
