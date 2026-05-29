extends Node2D

# Per-tile decay overlay covering the 192x192 map. Decay accumulates from any
# node in the "decay_emitter" group with a get_decay_radius() method (the
# Military structures do). Lootables read the value at their position to scale
# zombie spawn rates - 2x at 50+, 3x at 100+.
#
# Tile array is a single PackedFloat32Array indexed as tx + ty * MAP_TILES.
# Accumulation runs at EMIT_INTERVAL (twice per second is plenty given the
# 0.1/sec rate). Redraw runs at the same cadence; in early game almost all
# tiles are below the draw threshold, so the iteration is cheap.

const TILE_PX := 32
const MAP_TILES := 192
const MAX_DECAY := 150.0
const EMIT_INTERVAL := 0.5
const EMIT_PER_SEC := 0.1
const DRAW_THRESHOLD := 5.0
const DRAW_REFRESH_INTERVAL := 0.5
const DECAY_COLOR := Color(0.55, 0.18, 0.14)

var _grid: PackedFloat32Array
var _emit_timer: float = 0.0
var _draw_timer: float = 0.0


func _ready() -> void:
	add_to_group("decay_field")
	_grid = PackedFloat32Array()
	_grid.resize(MAP_TILES * MAP_TILES)
	# Render above ground tiles but below buildings/units. Runtime-added children
	# of Main default to z_index = 0 (with later tree order), so -5 puts us under
	# them; ground tiles paint via TileMapLayer at default z which we sit above.
	z_index = -5


func _process(delta: float) -> void:
	_emit_timer += delta
	if _emit_timer >= EMIT_INTERVAL:
		var elapsed: float = _emit_timer
		_emit_timer = 0.0
		_accumulate(elapsed * EMIT_PER_SEC)
	_draw_timer += delta
	if _draw_timer >= DRAW_REFRESH_INTERVAL:
		_draw_timer = 0.0
		queue_redraw()


func _accumulate(amount_per_tile: float) -> void:
	for e in get_tree().get_nodes_in_group("decay_emitter"):
		if not is_instance_valid(e):
			continue
		if not e.has_method("get_decay_radius"):
			continue
		var radius_tiles: float = e.get_decay_radius()
		var ri: int = int(ceil(radius_tiles))
		var cx: int = int(e.position.x / TILE_PX)
		var cy: int = int(e.position.y / TILE_PX)
		var r_sq: float = radius_tiles * radius_tiles
		var x_lo: int = max(0, cx - ri)
		var x_hi: int = min(MAP_TILES - 1, cx + ri)
		var y_lo: int = max(0, cy - ri)
		var y_hi: int = min(MAP_TILES - 1, cy + ri)
		for tx in range(x_lo, x_hi + 1):
			for ty in range(y_lo, y_hi + 1):
				var dx: float = float(tx - cx)
				var dy: float = float(ty - cy)
				if dx * dx + dy * dy > r_sq:
					continue
				var i: int = tx + ty * MAP_TILES
				var v: float = _grid[i] + amount_per_tile
				if v > MAX_DECAY:
					v = MAX_DECAY
				_grid[i] = v


func get_value_at(world_pos: Vector2) -> float:
	var tx: int = int(world_pos.x / TILE_PX)
	var ty: int = int(world_pos.y / TILE_PX)
	if tx < 0 or tx >= MAP_TILES or ty < 0 or ty >= MAP_TILES:
		return 0.0
	return _grid[tx + ty * MAP_TILES]


func _draw() -> void:
	# Each decayed tile renders as an iso diamond centered on the iso
	# projection of its world-coord tile center. Same diamond shape and size
	# as the iso ground tiles below so decay reads as a stain ON the ground,
	# not floating squares over it.
	var alpha_scale: float = 0.55 / MAX_DECAY
	var half_w: float = IsoView.ISO_TILE_W * 0.5
	var half_h: float = IsoView.ISO_TILE_H * 0.5
	var tile_w: float = float(TILE_PX)
	for ty in range(MAP_TILES):
		var row_offset: int = ty * MAP_TILES
		for tx in range(MAP_TILES):
			var v: float = _grid[tx + row_offset]
			if v < DRAW_THRESHOLD:
				continue
			var world_center := Vector2(
				float(tx) * tile_w + tile_w * 0.5,
				float(ty) * tile_w + tile_w * 0.5,
			)
			var iso_center: Vector2 = IsoView.world_to_screen(world_center)
			var c := Color(DECAY_COLOR.r, DECAY_COLOR.g, DECAY_COLOR.b, v * alpha_scale)
			draw_colored_polygon(PackedVector2Array([
				iso_center + Vector2(0.0, -half_h),
				iso_center + Vector2(half_w, 0.0),
				iso_center + Vector2(0.0, half_h),
				iso_center + Vector2(-half_w, 0.0),
			]), c)
