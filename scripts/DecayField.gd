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
# Slow ambient imagery (DESIGN_MASTER §2 demoted decay to visual-only intel),
# so the redraw cadence dropped from 2 Hz (0.5s) to 1 Hz here. The 2026-06-08
# perf pass also added viewport culling in _draw, so even the 1 Hz redraws are
# cheap regardless of how many off-screen tiles are decayed.
const DRAW_REFRESH_INTERVAL := 1.0
# How many pixels of slack to add around the visible rect when culling. One
# full iso tile of padding so tiles that are half off-screen still draw.
const CULL_PADDING_PX := 64.0
const DECAY_COLOR := Color(0.55, 0.18, 0.14)

var _grid: PackedFloat32Array
var _emit_timer: float = 0.0
var _draw_timer: float = 0.0
# Cached list of tile indices above DRAW_THRESHOLD. Rebuilt by _accumulate
# (2 Hz, when decay actually changes); _draw iterates this cache instead of
# the full 36864-tile grid. Decay only ever accumulates (never decreases) so
# the active set grows monotonically.
var _active_indices: PackedInt32Array = PackedInt32Array()
# Perf instrumentation - PerfProbe surfaces these in its probes.
# _last_active_tiles is the total monotonic decay-coverage size; _last_drawn
# is the post-viewport-cull count actually submitted to draw. They're equal
# pre-cull (legacy / headless w/o camera); post-cull the latter is the real
# per-frame cost driver.
var _last_draw_us: int = 0
var _last_active_tiles: int = 0
var _last_drawn: int = 0


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
	# Track newly-active tile indices so _draw doesn't need to scan all
	# 36864 tiles. _was_active flags by index: only append to
	# _active_indices when a tile first crosses DRAW_THRESHOLD.
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
				var prev: float = _grid[i]
				var v: float = prev + amount_per_tile
				if v > MAX_DECAY:
					v = MAX_DECAY
				_grid[i] = v
				# First-time crossing of the draw threshold -> add to the
				# active set. Once added, the tile stays (decay is
				# monotonic - no decrease path).
				if prev < DRAW_THRESHOLD and v >= DRAW_THRESHOLD:
					_active_indices.append(i)


func get_value_at(world_pos: Vector2) -> float:
	var tx: int = int(world_pos.x / TILE_PX)
	var ty: int = int(world_pos.y / TILE_PX)
	if tx < 0 or tx >= MAP_TILES or ty < 0 or ty >= MAP_TILES:
		return 0.0
	return _grid[tx + ty * MAP_TILES]


func _draw() -> void:
	# Iterate the cached active-tile list (decay only ever accumulates, so
	# inactive tiles never enter this list to begin with).
	#
	# Viewport cull (2026-06-08). _active_indices grows monotonically -
	# a 2-hr match could have tens of thousands of decayed tiles - so the
	# per-frame cost has to be bounded by what's actually visible, not by
	# total decay coverage. Decay was demoted to visual-only intel imagery
	# (DESIGN_MASTER §2): no sim consequence to skipping off-screen tiles.
	# Skip = no iso projection, no polygon submission.
	var t0_us: int = Time.get_ticks_usec()
	var alpha_scale: float = 0.55 / MAX_DECAY
	var half_w: float = IsoView.ISO_TILE_W * 0.5
	var half_h: float = IsoView.ISO_TILE_H * 0.5
	var tile_w: float = float(TILE_PX)
	# Compute the iso-screen-space visible rect from the active Camera2D.
	# Cull is gated on cam != null so headless / non-Camera2D scenes still
	# render the legacy "draw all active" path (cull off => prior behavior).
	var cull_enabled: bool = false
	var cull_rect: Rect2 = Rect2()
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var zoom: Vector2 = cam.zoom
		if zoom.x > 0.0001 and zoom.y > 0.0001:
			var visible_size := Vector2(
				get_viewport_rect().size.x / zoom.x,
				get_viewport_rect().size.y / zoom.y,
			)
			var pad := Vector2(CULL_PADDING_PX, CULL_PADDING_PX)
			cull_rect = Rect2(
				cam.global_position - visible_size * 0.5 - pad,
				visible_size + pad * 2.0,
			)
			cull_enabled = true
	var drawn: int = 0
	for idx in _active_indices:
		var v: float = _grid[idx]
		var ty: int = idx / MAP_TILES
		var tx: int = idx - ty * MAP_TILES
		var world_center := Vector2(
			float(tx) * tile_w + tile_w * 0.5,
			float(ty) * tile_w + tile_w * 0.5,
		)
		var iso_center: Vector2 = IsoView.world_to_screen(world_center)
		if cull_enabled and not cull_rect.has_point(iso_center):
			continue
		var c := Color(DECAY_COLOR.r, DECAY_COLOR.g, DECAY_COLOR.b, v * alpha_scale)
		draw_colored_polygon(PackedVector2Array([
			iso_center + Vector2(0.0, -half_h),
			iso_center + Vector2(half_w, 0.0),
			iso_center + Vector2(0.0, half_h),
			iso_center + Vector2(-half_w, 0.0),
		]), c)
		drawn += 1
	_last_draw_us = Time.get_ticks_usec() - t0_us
	_last_active_tiles = _active_indices.size()
	_last_drawn = drawn
