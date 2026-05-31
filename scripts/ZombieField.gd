extends Node2D

# Aggregate ecology layer for zombies. Holds two coarse-resolution grids:
#
#   density: number of zombies per 4-tile cell, updated every ~2.5 sec.
#            Drives gravitational pooling - zombies wander-bias toward
#            cells with moderate density, away from saturated ones.
#
#   residue: float-valued "attention residue" deposited by noise events,
#            exponentially decaying at 2%/sec. Drives slow persistent
#            attraction to combat sites - zombies drift in for minutes
#            after the original noise has passed.
#
# Grid resolution: 48x48 cells, each cell = 4 tiles = 128 px. Both grids
# share the same indexing so a single (cx, cy) lookup serves both.
#
# Updates run at low frequency on this single node, queried by every
# zombie at direction-change time only - so even with hundreds of
# zombies the per-zombie cost is one indexed lookup, not a scan.

const TILE_PX := 32
const MAP_TILES := 192
const CELL_TILES := 4
const CELL_PX := TILE_PX * CELL_TILES        # 128
const GRID_SIZE := MAP_TILES / CELL_TILES    # 48
const TOTAL_CELLS := GRID_SIZE * GRID_SIZE   # 2304

const DENSITY_UPDATE_INTERVAL := 2.5
const RESIDUE_DECAY_INTERVAL := 1.0
const RESIDUE_DECAY_MULT := 0.98             # 2% per sec exponential decay

# Density score buckets. Lower-end thresholds added so even ONE other
# zombie in a cell registers as attractive - on sparse maps the original
# 3+ floor produced cold-start failure where clusters never seeded.
const DENSITY_SCORE_OVERPACK_THRESHOLD := 16
const DENSITY_SCORE_TIER3_THRESHOLD := 11
const DENSITY_SCORE_TIER2_THRESHOLD := 6
const DENSITY_SCORE_TIER1_THRESHOLD := 3
const DENSITY_SCORE_LOW_HIGH_THRESHOLD := 2  # 2 zombies in cell
const DENSITY_SCORE_LOW_LOW_THRESHOLD := 1   # even 1 other zombie has gravity
const DENSITY_SCORE_OVERPACK := -0.5
const DENSITY_SCORE_TIER3 := 1.2
const DENSITY_SCORE_TIER2 := 1.0
const DENSITY_SCORE_TIER1 := 0.6
const DENSITY_SCORE_LOW_HIGH := 0.35
const DENSITY_SCORE_LOW_LOW := 0.18

# Residue contribution to direction score: cap so it never dominates,
# scale so it requires meaningful magnitude to register.
const RESIDUE_SCORE_SCALE := 0.05
const RESIDUE_SCORE_CAP := 1.0

# Residue radial deposition: 0/1-2/3-4 cell rings.
const RESIDUE_DEPOSIT_RADIUS := 4
const RESIDUE_CENTER_FACTOR := 1.0
const RESIDUE_ADJACENT_FACTOR := 0.5
const RESIDUE_OUTER_FACTOR := 0.25

var _density: PackedInt32Array
var _residue: PackedFloat32Array
var _density_timer: float = 0.0
var _residue_timer: float = 0.0


func _ready() -> void:
	add_to_group("zombie_field")
	_density = PackedInt32Array()
	_density.resize(TOTAL_CELLS)
	_residue = PackedFloat32Array()
	_residue.resize(TOTAL_CELLS)


func _process(delta: float) -> void:
	_density_timer += delta
	if _density_timer >= DENSITY_UPDATE_INTERVAL:
		_density_timer = 0.0
		_recompute_density()
	_residue_timer += delta
	if _residue_timer >= RESIDUE_DECAY_INTERVAL:
		_residue_timer -= RESIDUE_DECAY_INTERVAL
		_decay_residue()


# Single pass through all zombies; cheap with the coarse grid.
func _recompute_density() -> void:
	for i in range(_density.size()):
		_density[i] = 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if u.faction != 2:  # Unit.Faction.ZOMBIE
			continue
		var cell := _world_to_cell(u.global_position)
		if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
			continue
		_density[cell.x + cell.y * GRID_SIZE] += 1


func _decay_residue() -> void:
	for i in range(_residue.size()):
		_residue[i] *= RESIDUE_DECAY_MULT


func _world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_PX), int(world_pos.y / CELL_PX))


# --- Density queries ---


func get_density_at(world_pos: Vector2) -> int:
	var cell := _world_to_cell(world_pos)
	if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
		return 0
	return _density[cell.x + cell.y * GRID_SIZE]


func density_score(world_pos: Vector2) -> float:
	# Cells over the overpack threshold push zombies outward; cells with
	# even one zombie now produce a small pull so cold-start clustering
	# actually seeds.
	var n: int = get_density_at(world_pos)
	if n >= DENSITY_SCORE_OVERPACK_THRESHOLD:
		return DENSITY_SCORE_OVERPACK
	if n >= DENSITY_SCORE_TIER3_THRESHOLD:
		return DENSITY_SCORE_TIER3
	if n >= DENSITY_SCORE_TIER2_THRESHOLD:
		return DENSITY_SCORE_TIER2
	if n >= DENSITY_SCORE_TIER1_THRESHOLD:
		return DENSITY_SCORE_TIER1
	if n >= DENSITY_SCORE_LOW_HIGH_THRESHOLD:
		return DENSITY_SCORE_LOW_HIGH
	if n >= DENSITY_SCORE_LOW_LOW_THRESHOLD:
		return DENSITY_SCORE_LOW_LOW
	return 0.0


# --- Residue queries ---


func get_residue_at(world_pos: Vector2) -> float:
	var cell := _world_to_cell(world_pos)
	if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
		return 0.0
	return _residue[cell.x + cell.y * GRID_SIZE]


func residue_score(world_pos: Vector2) -> float:
	return minf(get_residue_at(world_pos) * RESIDUE_SCORE_SCALE, RESIDUE_SCORE_CAP)


func deposit_residue(world_pos: Vector2, magnitude: float) -> void:
	# Radial deposit: center cell + 1-2 ring + 3-4 ring at falling factors.
	var center := _world_to_cell(world_pos)
	for dx in range(-RESIDUE_DEPOSIT_RADIUS, RESIDUE_DEPOSIT_RADIUS + 1):
		for dy in range(-RESIDUE_DEPOSIT_RADIUS, RESIDUE_DEPOSIT_RADIUS + 1):
			var nx: int = center.x + dx
			var ny: int = center.y + dy
			if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
				continue
			# Chebyshev distance for square rings.
			var d: int = max(absi(dx), absi(dy))
			var factor: float
			if d == 0:
				factor = RESIDUE_CENTER_FACTOR
			elif d <= 2:
				factor = RESIDUE_ADJACENT_FACTOR
			elif d <= 4:
				factor = RESIDUE_OUTER_FACTOR
			else:
				continue
			_residue[nx + ny * GRID_SIZE] += magnitude * factor
