extends Control


func _ready() -> void:
	# --ai-vs-ai bypass: headless balance-lab mode (e.g. CI / nightly batches)
	# cannot click buttons. Detect the flag and transition straight to Main
	# with the AI-vs-AI flag set on GameState. Defaults: Military vs Military,
	# AI enabled, procedural map. --seed=N is consumed downstream by
	# GameState.reset_match for the SimRng seed.
	if "--ai-vs-ai" in OS.get_cmdline_user_args():
		GameState.player_faction = GameState.Faction.MILITARY
		GameState.ai_enabled = true
		GameState.ai_vs_ai_mode = true
		GameState.custom_map_path = ""
		# Deferred: the SceneTree is mid-add when our _ready fires, so a
		# synchronous change_scene_to_file errors with "parent node is busy
		# adding/removing children". One-tick deferral lets the tree settle.
		get_tree().call_deferred("change_scene_to_file", "res://scenes/Main.tscn")
		return
	# Diagnostic hook (2026-06-08): --repro-hg-horde transitions to Main as a
	# Military player with no AI opponent. Main._ready detects the same flag
	# and spawns the focused HG-vs-horde scenario (see _repro_hg_horde).
	if "--repro-hg-horde" in OS.get_cmdline_user_args():
		GameState.player_faction = GameState.Faction.MILITARY
		GameState.ai_enabled = false
		GameState.ai_vs_ai_mode = false
		GameState.custom_map_path = ""
		get_tree().call_deferred("change_scene_to_file", "res://scenes/Main.tscn")
		return
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
