extends Node

# One-shot headless test for the (unconnected) Survivor roster. Run as a
# SCENE (not -s) so project autoloads register and scripts fully compile:
#   godot --headless res://tools/SurvivorSceneTest.tscn --path .

const SCENES := [
	"res://scenes/units/Bolter.tscn",
	"res://scenes/units/Chemist.tscn",
	"res://scenes/units/Saboteur.tscn",
	"res://scenes/units/Builder.tscn",
	"res://scenes/units/SurvivorRunner.tscn",
	"res://scenes/buildings/Farm.tscn",
	"res://scenes/buildings/RadioStation.tscn",
	"res://scenes/buildings/SettlementHub.tscn",
]


func _ready() -> void:
	var failures := 0
	for path in SCENES:
		var ps: PackedScene = load(path)
		if ps == null:
			print("FAIL load: %s" % path)
			failures += 1
			continue
		var node = ps.instantiate()
		if node == null:
			print("FAIL instantiate: %s" % path)
			failures += 1
			continue
		# add_child exercises _ready (sprite init, group joins) — the real test.
		add_child(node)
		print("OK %s (%s, faction=%s, hp=%s)" % [path, node.name, str(node.get("faction")), str(node.get("max_hp"))])
	print("RESULT: %d/%d ok" % [SCENES.size() - failures, SCENES.size()])
	get_tree().quit(1 if failures > 0 else 0)
