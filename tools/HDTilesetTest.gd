extends Node2D

# HD tileset style test (2026-06-11): renders a small diorama from the
# "2D HD Zombie Rural Tileset" pack next to our pixel-art unit sprites,
# so Matt can judge the HD-environment + pixel-character mix with his
# own eyes before any pipeline decision. Dev tool, not wired into play.
#   godot --headless? NO - needs rendering: godot res://tools/HDTilesetTest.tscn --path .
# Saves hd_test.png and quits.

const DIR := "res://assets/hd_test/"
const SCALE := 0.5  # pack tiles are 128x64 faces = exactly 2x ours


func _ready() -> void:
	# Ground patch: 8x8 diamond of dirt with a few dark-asphalt cells.
	var ground_a: Texture2D = _load(DIR + "Ground A1_S.png")
	var ground_a2: Texture2D = _load(DIR + "Ground A2_S.png")
	var ground_b: Texture2D = _load(DIR + "Ground B1_S.png")
	for gy in range(8):
		for gx in range(8):
			var tex: Texture2D = ground_a if (gx * 7 + gy * 13) % 3 != 0 else ground_a2
			if gy >= 5 and gx <= 3:
				tex = ground_b  # road corner
			_sprite(tex, Vector2((gx - gy) * 32, (gx + gy) * 16), (gx + gy))
	# Props on top.
	_sprite(_load(DIR + "Car1_S.png"), Vector2(-40, 90), 200)
	_sprite(_load(DIR + "Car3_S.png"), Vector2(90, 130), 210)
	_sprite(_load(DIR + "Tree A1_S.png"), Vector2(140, 40), 150)
	_sprite(_load(DIR + "Object1_S.png"), Vector2(-100, 60), 160)
	_sprite(_load(DIR + "Fence A1_S.png"), Vector2(30, 20), 140)
	# Our pixel-art units beside the HD props: the style-mix verdict.
	_unit_sprite("res://assets/sprites/units/military/rifleman/idle/south/0.png", Vector2(0, 100))
	_unit_sprite("res://assets/sprites/units/survivor/bolter/idle/south/0.png", Vector2(40, 115))
	_unit_sprite("res://assets/sprites/units/zombies/shambler/idle/south/0.png", Vector2(80, 95))
	var cam := Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position = Vector2(0, 100)
	add_child(cam)
	cam.make_current()
	_snap()


func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _sprite(tex: Texture2D, pos: Vector2, z: int) -> void:
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2(SCALE, SCALE)
	s.z_index = z
	# Pack art is bottom-heavy in tall canvases: anchor near the base.
	s.offset = Vector2(0, -tex.get_size().y * 0.5 + 32)
	add_child(s)


func _unit_sprite(path: String, pos: Vector2) -> void:
	var tex: Texture2D = _load(path)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.z_index = 300
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)


func _snap() -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://hd_test.png")
	print("[HDTest] saved")
	get_tree().quit()
