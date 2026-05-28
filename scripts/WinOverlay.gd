extends CanvasLayer

# End-of-match overlay. Pauses the tree, shows VICTORY or DEFEAT, restart button
# reloads Main. Set process_mode = ALWAYS so the button stays interactive while
# the rest of the tree is paused.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Panel/VBox/RestartButton.pressed.connect(_on_restart)
	$Panel/VBox/QuitButton.pressed.connect(_on_quit)


func show_victory() -> void:
	_show("VICTORY", Color(0.45, 0.85, 0.45))


func show_defeat() -> void:
	_show("DEFEAT", Color(0.85, 0.4, 0.35))


func _show(text: String, color: Color) -> void:
	$Panel/VBox/Title.text = text
	$Panel/VBox/Title.modulate = color
	visible = true
	get_tree().paused = true


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
