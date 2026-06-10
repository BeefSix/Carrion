extends RefCounted

# Faction strategy DATA (AI_OVERHAUL_PLAN.md §2, approved 2026-06-10).
# The strategist reads one of these dictionaries and contains zero faction
# `if`s. Difficulty later = a multiplier table over these numbers, not new
# code (Decision A: ship one default tuned to "beats a first-time player,
# loses to a focused one"; difficulty SETTINGS are out of scope until
# campaign work).
#
# Determinism: everything here is const data. The sustain list is consumed
# ROUND-ROBIN (never randomly) so composition is reproducible. All values
# are lab placeholders; A6 tunes them — and A6's numbers are explicitly
# PROVISIONAL until the threat pass re-tune (A6b, see ROADMAP.md).
#
# Profile keys:
#   build_order: Array of {item, cost, time, needs_production_building}
#       — the canonical opening, consumed once, in order.
#   sustain: Array of the same row shape — consumed round-robin forever
#       after the build order is exhausted (A3 adds composition mixes).
#   recovery_worker / recovery_production_building: H2 stall-recovery
#       templates, re-emitted without consuming the build-order step.
#   economy_floor: below this many workers the economy counts as dead and
#       a recovery worker preempts everything (SURVIVE slots above this
#       in A2).
#   production_building_step: build_order index AFTER which the production
#       building must exist (recovery triggers if it died).
#   worker_script: script path identifying the faction's economy unit for
#       the stall-recovery count.
#   attack_threshold / retreat_fraction: army posture numbers (unchanged
#       from the pre-profile constants).

const MILITARY := {
	"build_order": [
		{ "item": "looter",   "cost": 50,  "time": 18.0, "needs_production_building": false },
		{ "item": "looter",   "cost": 50,  "time": 18.0, "needs_production_building": false },
		{ "item": "barracks", "cost": 200, "time": 50.0, "needs_production_building": false },
		{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_production_building": true },
		{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_production_building": true },
		{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_production_building": true },
		{ "item": "rifleman", "cost": 75,  "time": 25.0, "needs_production_building": true },
	],
	"sustain": [
		{ "item": "rifleman", "cost": 75, "time": 25.0, "needs_production_building": true },
	],
	"recovery_worker": { "item": "looter", "cost": 50, "time": 18.0, "needs_production_building": false },
	"recovery_production_building": { "item": "barracks", "cost": 200, "time": 50.0, "needs_production_building": false },
	"economy_floor": 1,
	"production_building_step": 3,
	"worker_script": "res://scripts/Looter.gd",
	"attack_threshold": 6,
	"retreat_fraction": 0.6,
	# A2: sim-seconds of base quiet before standing down from DEFEND. Long
	# enough to not flicker between waves of one assault; short enough that
	# a feint doesn't pin the army home forever.
	"defend_cooldown": 15.0,
}

# A4 fills this in (Walkers -> Hunting Lodge -> Hunters -> Ritual Site ->
# Shaman). Declared now so profile_for has a stable shape to grow into.
const TRIBAL := {}


static func profile_for(faction: int) -> Dictionary:
	# GameState.Faction.TRIBAL == 1; everything else falls back to the
	# Military profile until A4 lands the Tribal one.
	if faction == 1 and not TRIBAL.is_empty():
		return TRIBAL
	return MILITARY
