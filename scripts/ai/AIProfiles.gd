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
	# A3: composition mix, consumed round-robin (3:1 rifle:HG per the plan's
	# example ratio). The HG is the Military group-clear identity piece; its
	# AI build time is scaled the same way the rifleman's is vs player times.
	"sustain": [
		{ "item": "rifleman", "cost": 75, "time": 25.0, "needs_production_building": true },
		{ "item": "rifleman", "cost": 75, "time": 25.0, "needs_production_building": true },
		{ "item": "rifleman", "cost": 75, "time": 25.0, "needs_production_building": true },
		{ "item": "heavy_gunner", "cost": 225, "time": 35.0, "needs_production_building": true },
	],
	"recovery_worker": { "item": "looter", "cost": 50, "time": 18.0, "needs_production_building": false },
	"recovery_production_building": { "item": "barracks", "cost": 200, "time": 50.0, "needs_production_building": false },
	"economy_floor": 1,
	# A3: ECONOMY GROWTH targets — [sim_minute, worker_count] steps, evaluated
	# as "the latest step whose minute has passed". The build order already
	# fields 2 workers; this grows the economy to 4 by minute 6 instead of
	# the old behavior (never builds a third Looter, salvage flatlines).
	"worker_targets": [[0, 2], [3, 3], [6, 4]],
	"production_building_step": 3,
	"worker_script": "res://scripts/Looter.gd",
	"attack_threshold": 6,
	"retreat_fraction": 0.6,
	# A2: sim-seconds of base quiet before standing down from DEFEND. Long
	# enough to not flicker between waves of one assault; short enough that
	# a feint doesn't pin the army home forever.
	"defend_cooldown": 15.0,
	# A5 (approved defaults): harassment starts at minute 4, peels 2 units
	# every 90s at the most exposed enemy worker, only while the army is at
	# or above the attack threshold (never strips a small defense).
	"harass_start": 240.0,
	"harass_squad": 2,
	"harass_interval": 90.0,
}

# A4 (2026-06-10): the Tribal strategy. Costs mirror the player buildings
# (TribalCamp/HuntingLodge/RitualSite consts); AI build times use the same
# ~2.5-3x scale the Military profile applies vs player times. Identity
# choices: attack_threshold 4 (Strike/Withdraw — earlier, smaller commits
# than Military's mass-and-push 6) and uses_shaman (the strategist sends
# idle Shamans to ritual at the infested building nearest the ENEMY HQ —
# approved default C — making "zombies as a weapon" an AI behavior).
const TRIBAL := {
	"build_order": [
		{ "item": "walker", "cost": 50, "time": 20.0, "needs_production_building": false },
		{ "item": "walker", "cost": 50, "time": 20.0, "needs_production_building": false },
		{ "item": "hunting_lodge", "cost": 150, "time": 45.0, "needs_production_building": false },
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
		{ "item": "ritual_site", "cost": 200, "time": 50.0, "needs_production_building": false },
		{ "item": "shaman", "cost": 100, "time": 30.0, "needs_tech_building": true },
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
	],
	"sustain": [
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
		{ "item": "hunter", "cost": 50, "time": 25.0, "needs_production_building": true },
		{ "item": "shaman", "cost": 100, "time": 30.0, "needs_tech_building": true },
	],
	"recovery_worker": { "item": "walker", "cost": 50, "time": 20.0, "needs_production_building": false },
	"recovery_production_building": { "item": "hunting_lodge", "cost": 150, "time": 45.0, "needs_production_building": false },
	"economy_floor": 1,
	"worker_targets": [[0, 2], [3, 3], [6, 4]],
	"production_building_step": 3,
	"worker_script": "res://scripts/Walker.gd",
	"attack_threshold": 4,
	"retreat_fraction": 0.6,
	"defend_cooldown": 15.0,
	"uses_shaman": true,
	# Min sim-seconds between ritual ORDERS. Without it the first MT lab run
	# was a ritual every ~6s at the enemy's doorstep — an unstoppable zombie
	# hose that won by minute 2 and drained every coin (sustain starved).
	# 45s makes each ritual a punctuating wave, not a faucet. Lab-tunable.
	"forcespawn_interval": 45.0,
	# Earliest sim-second for the FIRST ritual (same anti-rush logic as the
	# approved harass-start default): a doorstep ritual at 0.9 min still won
	# by minute 2 even at the 45s cadence — no opening can answer it. 150s
	# lets both factions' openings mature before zombies become a weapon.
	"forcespawn_start": 150.0,
	# A5: Tribal harasses too — slightly earlier and in the same small
	# packs as its Strike identity.
	"harass_start": 210.0,
	"harass_squad": 2,
	"harass_interval": 90.0,
}


static func profile_for(faction: int) -> Dictionary:
	# GameState.Faction.TRIBAL == 1; everything else falls back to the
	# Military profile until A4 lands the Tribal one.
	if faction == 1 and not TRIBAL.is_empty():
		return TRIBAL
	return MILITARY
