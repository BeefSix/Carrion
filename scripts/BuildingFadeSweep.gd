extends Node

# Occlusion-fade sweep (2026-06-11, replaces per-building self-polling
# which hitched the frame 5x/sec — every building scanned the units
# group on the same frame). RENDER-ONLY.
#
# One node, one pass: each _process frame handles a SLICE of the skinned
# buildings, so the cost is spread across frames instead of spiking. The
# units group is fetched once per frame and shared. Full sweep completes
# in SLICES frames (~0.2s at 60fps), matching the old cadence without
# the spike.

const SLICES := 12
# Hard cap on buildings processed per frame: at high building counts the
# slice itself gets big (902 buildings / 12 = 75/frame during the nav
# incident). Fades just react slower on huge maps - never a frame spike.
const MAX_PER_FRAME := 12

var _cursor: int = 0


func _process(_delta: float) -> void:
	var buildings: Array = get_tree().get_nodes_in_group("skinned_buildings")
	if buildings.is_empty():
		return
	var units: Array = get_tree().get_nodes_in_group("units")
	var per_frame: int = mini(MAX_PER_FRAME, maxi(1, int(ceil(float(buildings.size()) / float(SLICES)))))
	for i in range(per_frame):
		var idx: int = (_cursor + i) % buildings.size()
		var b = buildings[idx]
		if is_instance_valid(b) and b.has_method("update_fade"):
			b.update_fade(units)
	_cursor = (_cursor + per_frame) % maxi(buildings.size(), 1)
