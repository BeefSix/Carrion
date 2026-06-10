extends RefCounted

# Build catalog — the data behind SC-style worker construction (Matt
# directive 2026-06-10: "drag and drop buildings where the resource units
# build them"). Workers are the builders per canon: DESIGN_MASTER §7.1
# names the LOOTER the Military builder (Engineer keeps walls + repair);
# the Walker builds Tribal's minimal footprint.
#
# Per entry: scene (the real building), cost, build_time (worker channel
# seconds at the site), footprint (world px, drives the placement ghost +
# validity), display name. Costs/times match the old HQ-queue rows they
# replace, so the macro economy is unchanged — only the VERB moved (queue
# click -> place + worker builds).

const MILITARY := {
	"barracks": {
		"name": "Barracks", "scene": "res://scenes/buildings/Barracks.tscn",
		"cost": 200, "build_time": 50.0, "footprint": Vector2(96, 96),
	},
}

const TRIBAL := {
	"hunting_lodge": {
		"name": "Hunting Lodge", "scene": "res://scenes/buildings/HuntingLodge.tscn",
		"cost": 150, "build_time": 45.0, "footprint": Vector2(96, 96),
	},
	"ritual_site": {
		"name": "Ritual Site", "scene": "res://scenes/buildings/RitualSite.tscn",
		"cost": 200, "build_time": 50.0, "footprint": Vector2(96, 96),
	},
}


const SURVIVOR := {
	# DESIGN_MASTER §7.3: farms are the pylons; radios attach to farms and
	# carry the economy. Costs/times are balance-lab placeholders sized
	# against the Military barracks row. Connected 2026-06-10: the
	# SettlementHub-produced Builder reads this table.
	"farm": {
		"name": "Farm", "scene": "res://scenes/buildings/Farm.tscn",
		"cost": 150, "build_time": 40.0, "footprint": Vector2(96, 96),
	},
	"radio_station": {
		"name": "Radio Station", "scene": "res://scenes/buildings/RadioStation.tscn",
		"cost": 200, "build_time": 50.0, "footprint": Vector2(64, 64),
	},
}


static func catalog_for(faction: int) -> Dictionary:
	# GameState.Faction: TRIBAL == 1, SURVIVOR == 4.
	if faction == 1:
		return TRIBAL
	if faction == 4:
		return SURVIVOR
	return MILITARY


static func entry(faction: int, key: String) -> Dictionary:
	return catalog_for(faction).get(key, {})
