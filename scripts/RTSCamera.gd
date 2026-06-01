extends Camera2D

const PAN_SPEED := 600.0
const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5


func _ready() -> void:
	add_to_group("rts_camera")


# Jump the camera to a world-space point. World coords stay in gameplay space;
# Camera2D lives in iso screen-space (Phase 2), so project before assigning.
func center_on_world(world_pos: Vector2) -> void:
	position = IsoView.world_to_screen(world_pos)


func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		direction.x += 1
	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= ZOOM_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom /= ZOOM_STEP
		else:
			return
		zoom = zoom.clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
