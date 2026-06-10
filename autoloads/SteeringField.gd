extends Node2D

# SteeringField v0 — the §3.2 keystone, approved 2026-06-10 (CALLER_PLAN
# phase B1, field-path delivery).
#
# ONE signed-weight influence system for all zombie movement: every
# influence (Caller whistle today; noise residue, scent, density, anchors,
# repulsors, home bias as they migrate) is an EMITTER with a position,
# signed weight (+attract / -repel), radius, and optional expiry. Zombie
# wander sampling reads sample_bias() — a deterministic Vector2 pull — and
# folds it into candidate scoring. v0 scope guard (per the approved plan):
# bias on WANDER DIRECTION only; CHASE/ATTACK untouched; no grid-blur or
# diffusion yet (the emitter list IS the field — a coarse cell cache can
# come when emitter counts demand it).
#
# Determinism (CLAUDE.md): physics-tick expiry only, no RNG, no physics
# queries, no transcendentals (vector math is +,*,/ and normalized()'s
# sqrt — sanctioned). Emitters are stored in insertion order; sampling
# SUMS over all emitters so iteration order cannot affect the result.
#
# This is also the architecture that retires NETCODE irreducible #1: as
# zombie movement migrates from move_and_slide physics onto field-driven
# deterministic integration, the CI's zombie-position noise goes away.

# Emitter: { "pos": Vector2, "weight": float (signed), "radius": float,
#            "expiry": float (sim-seconds; <0 = permanent), "id": int }
var _emitters: Array = []
var _next_id: int = 1


func _ready() -> void:
	add_to_group("steering_field")


func _physics_process(_delta: float) -> void:
	# Expiry sweep on the physics tick (sim-state mutation — rule #2).
	if _emitters.is_empty():
		return
	var now: float = GameState.sim_seconds()
	var kept: Array = []
	for e in _emitters:
		if float(e["expiry"]) < 0.0 or now < float(e["expiry"]):
			kept.append(e)
	_emitters = kept


# Add an influence. duration < 0 = permanent (caller removes by id).
# Returns the emitter id for later remove/refresh.
func add_emitter(pos: Vector2, weight: float, radius: float, duration: float = -1.0) -> int:
	var id: int = _next_id
	_next_id += 1
	_emitters.append({
		"pos": pos,
		"weight": weight,
		"radius": radius,
		"expiry": -1.0 if duration < 0.0 else GameState.sim_seconds() + duration,
		"id": id,
	})
	return id


func remove_emitter(id: int) -> void:
	for i in range(_emitters.size()):
		if int(_emitters[i]["id"]) == id:
			_emitters.remove_at(i)
			return


# Move/retarget an existing emitter (the Caller's whistle follows orders).
func update_emitter_pos(id: int, pos: Vector2) -> void:
	for e in _emitters:
		if int(e["id"]) == id:
			e["pos"] = pos
			return


# The read API: net pull vector at a world position. Each emitter
# contributes weight * falloff toward (or away from) itself; falloff is
# linear to zero at radius. Summed over all emitters — order-free.
func sample_bias(world_pos: Vector2) -> Vector2:
	if _emitters.is_empty():
		return Vector2.ZERO
	var bias: Vector2 = Vector2.ZERO
	for e in _emitters:
		var to_e: Vector2 = e["pos"] - world_pos
		var d: float = to_e.length()
		var r: float = float(e["radius"])
		if d >= r or d < 0.001:
			continue
		var falloff: float = 1.0 - d / r
		bias += to_e / d * float(e["weight"]) * falloff
	return bias


func emitter_count() -> int:
	return _emitters.size()
