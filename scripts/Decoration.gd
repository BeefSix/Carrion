extends Node2D

const MAP_SIZE := Vector2(2560, 2560)
const STREET_POSITIONS := [512.0, 1024.0, 1536.0, 2048.0]
const STREET_WIDTH := 48.0
const SIDEWALK_WIDTH := 8.0

const COLOR_STREET := Color("32281f")
const COLOR_STREET_CENTERLINE := Color("78706a")
const COLOR_SIDEWALK := Color("746a58")
const COLOR_HEDGE := Color("3a4a35")
const COLOR_TRASHCAN := Color("262220")
const COLOR_MAILBOX := Color("5a5246")
const COLOR_FENCE := Color("4a4036")
const COLOR_DRIVEWAY := Color("564a3f")

const TRASH_COUNT := 70
const HEDGE_COUNT := 45
const MAILBOX_COUNT := 30
const FENCE_COUNT := 25
const DRIVEWAY_COUNT := 18

const KEEPOUT_CENTERS := [Vector2(1280, 1280), Vector2(1280, 768)]
const KEEPOUT_RADIUS := 60.0
const STREET_AVOID_DECOR := 36.0

var _trash: Array = []
var _hedges: Array = []
var _mailboxes: Array = []
var _fences: Array = []  # each entry: [start, end]
var _driveways: Array = []  # each entry: position


func _ready() -> void:
	_generate_decor()
	queue_redraw()


func _generate_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(TRASH_COUNT):
		var p := _pick_decor_pos(rng)
		if p != Vector2.INF:
			_trash.append(p)
	for i in range(HEDGE_COUNT):
		var p := _pick_decor_pos(rng)
		if p != Vector2.INF:
			_hedges.append(p)
	for i in range(MAILBOX_COUNT):
		var p := _pick_decor_pos_near_street(rng)
		if p != Vector2.INF:
			_mailboxes.append(p)
	for i in range(FENCE_COUNT):
		var p := _pick_decor_pos(rng)
		if p == Vector2.INF:
			continue
		var horizontal: bool = rng.randf() < 0.5
		var length: float = rng.randf_range(40.0, 80.0)
		if horizontal:
			_fences.append([p, p + Vector2(length, 0)])
		else:
			_fences.append([p, p + Vector2(0, length)])
	for i in range(DRIVEWAY_COUNT):
		var p := _pick_driveway_pos(rng)
		if p != Vector2.INF:
			_driveways.append(p)


func _pick_decor_pos(rng: RandomNumberGenerator) -> Vector2:
	for attempt in range(40):
		var p := Vector2(rng.randf_range(40, MAP_SIZE.x - 40), rng.randf_range(40, MAP_SIZE.y - 40))
		if _is_on_street(p, STREET_AVOID_DECOR):
			continue
		if _is_near_keepout(p):
			continue
		return p
	return Vector2.INF


func _pick_decor_pos_near_street(rng: RandomNumberGenerator) -> Vector2:
	# Mailboxes belong on lawns near sidewalks. Pick a position close to a street but not on it.
	for attempt in range(40):
		var sx_or_sy: bool = rng.randf() < 0.5
		if sx_or_sy:
			var sx: float = STREET_POSITIONS[rng.randi() % STREET_POSITIONS.size()]
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			var offset: float = STREET_WIDTH * 0.5 + SIDEWALK_WIDTH + rng.randf_range(8.0, 20.0)
			var y: float = rng.randf_range(80.0, MAP_SIZE.y - 80.0)
			var p := Vector2(sx + side * offset, y)
			if not _is_near_keepout(p):
				return p
		else:
			var sy: float = STREET_POSITIONS[rng.randi() % STREET_POSITIONS.size()]
			var side2: float = 1.0 if rng.randf() < 0.5 else -1.0
			var offset2: float = STREET_WIDTH * 0.5 + SIDEWALK_WIDTH + rng.randf_range(8.0, 20.0)
			var x: float = rng.randf_range(80.0, MAP_SIZE.x - 80.0)
			var p2 := Vector2(x, sy + side2 * offset2)
			if not _is_near_keepout(p2):
				return p2
	return Vector2.INF


func _pick_driveway_pos(rng: RandomNumberGenerator) -> Vector2:
	for attempt in range(40):
		var sx_or_sy: bool = rng.randf() < 0.5
		if sx_or_sy:
			var sx: float = STREET_POSITIONS[rng.randi() % STREET_POSITIONS.size()]
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			var offset: float = STREET_WIDTH * 0.5 + SIDEWALK_WIDTH + rng.randf_range(0.0, 8.0)
			var y: float = rng.randf_range(80.0, MAP_SIZE.y - 80.0)
			var p := Vector2(sx + side * (offset + 12.0), y)
			if not _is_near_keepout(p):
				return p
		else:
			var sy: float = STREET_POSITIONS[rng.randi() % STREET_POSITIONS.size()]
			var side2: float = 1.0 if rng.randf() < 0.5 else -1.0
			var offset2: float = STREET_WIDTH * 0.5 + SIDEWALK_WIDTH + rng.randf_range(0.0, 8.0)
			var x: float = rng.randf_range(80.0, MAP_SIZE.x - 80.0)
			var p2 := Vector2(x, sy + side2 * (offset2 + 12.0))
			if not _is_near_keepout(p2):
				return p2
	return Vector2.INF


func _is_on_street(pos: Vector2, padding: float) -> bool:
	for sx in STREET_POSITIONS:
		if abs(pos.x - sx) < (STREET_WIDTH * 0.5 + padding):
			return true
	for sy in STREET_POSITIONS:
		if abs(pos.y - sy) < (STREET_WIDTH * 0.5 + padding):
			return true
	return false


func _is_near_keepout(pos: Vector2) -> bool:
	for c in KEEPOUT_CENTERS:
		if pos.distance_to(c) < KEEPOUT_RADIUS:
			return true
	return false


func _draw() -> void:
	# Sidewalks (drawn before street so the street covers part of them at intersections; the rest forms sidewalk strips)
	for sy in STREET_POSITIONS:
		draw_rect(Rect2(0, sy - STREET_WIDTH * 0.5 - SIDEWALK_WIDTH, MAP_SIZE.x, SIDEWALK_WIDTH), COLOR_SIDEWALK)
		draw_rect(Rect2(0, sy + STREET_WIDTH * 0.5, MAP_SIZE.x, SIDEWALK_WIDTH), COLOR_SIDEWALK)
	for sx in STREET_POSITIONS:
		draw_rect(Rect2(sx - STREET_WIDTH * 0.5 - SIDEWALK_WIDTH, 0, SIDEWALK_WIDTH, MAP_SIZE.y), COLOR_SIDEWALK)
		draw_rect(Rect2(sx + STREET_WIDTH * 0.5, 0, SIDEWALK_WIDTH, MAP_SIZE.y), COLOR_SIDEWALK)

	# Streets
	for sy in STREET_POSITIONS:
		draw_rect(Rect2(0, sy - STREET_WIDTH * 0.5, MAP_SIZE.x, STREET_WIDTH), COLOR_STREET)
	for sx in STREET_POSITIONS:
		draw_rect(Rect2(sx - STREET_WIDTH * 0.5, 0, STREET_WIDTH, MAP_SIZE.y), COLOR_STREET)

	# Centerline dashes (subtle)
	for sy in STREET_POSITIONS:
		var x: float = 0.0
		while x < MAP_SIZE.x:
			draw_rect(Rect2(x, sy - 1.0, 16.0, 2.0), COLOR_STREET_CENTERLINE)
			x += 40.0
	for sx in STREET_POSITIONS:
		var y: float = 0.0
		while y < MAP_SIZE.y:
			draw_rect(Rect2(sx - 1.0, y, 2.0, 16.0), COLOR_STREET_CENTERLINE)
			y += 40.0

	# Driveways (light paved patches next to streets)
	for d in _driveways:
		var driveway_size := Vector2(20.0, 28.0)
		draw_rect(Rect2(d - driveway_size * 0.5, driveway_size), COLOR_DRIVEWAY)

	# Hedges
	for h in _hedges:
		var hedge_size := Vector2(18.0, 7.0)
		draw_rect(Rect2(h - hedge_size * 0.5, hedge_size), COLOR_HEDGE)

	# Fences
	for f in _fences:
		draw_line(f[0], f[1], COLOR_FENCE, 2.0, true)

	# Mailboxes
	for m in _mailboxes:
		draw_rect(Rect2(m - Vector2(2.5, 5.0), Vector2(5.0, 10.0)), COLOR_MAILBOX)

	# Trash cans
	for t in _trash:
		draw_circle(t, 3.5, COLOR_TRASHCAN)
