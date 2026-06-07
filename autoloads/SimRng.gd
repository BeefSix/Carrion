extends Node

# Single seeded RNG owned by the sim per CLAUDE.md Determinism Rule #1.
# All gameplay randomness must route through this so future lockstep
# multiplayer can be reproducible. Visual-only randomness (particle wobble,
# sprite variation) may stay on bare randf() but must NEVER feed back into
# gameplay state.
#
# Existing per-script randf() calls are grandfathered (large surface to
# migrate); convert them whenever you touch the surrounding code. New code
# uses SimRng unconditionally.
#
# `tick` is the call counter - tests can seed, spin N steps, and assert
# reproducibility of the resulting sequence.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var tick: int = 0


func seed_with(s: int) -> void:
	# Named seed_with instead of seed() because Node already has a virtual
	# named seed in some contexts; avoid ambiguity at call sites.
	_rng.seed = s
	tick = 0


func randf() -> float:
	tick += 1
	return _rng.randf()


func randf_range(lo: float, hi: float) -> float:
	tick += 1
	return _rng.randf_range(lo, hi)


func randi() -> int:
	tick += 1
	return _rng.randi()


func randi_range(lo: int, hi: int) -> int:
	tick += 1
	return _rng.randi_range(lo, hi)


func pick(arr: Array):
	if arr.is_empty():
		return null
	tick += 1
	return arr[_rng.randi() % arr.size()]


func chance(p: float) -> bool:
	tick += 1
	return _rng.randf() < p
