extends Node

# Thin emit helper. Looks up the NoiseField in the scene tree by group and
# routes the emit call. Replaces the 7 copy-paste sites that previously did:
#     var nf := get_tree().get_first_node_in_group("noise_field")
#     if nf != null: nf.add_noise(pos, mag)
# Centralizing means future noise behavior (faction multipliers, mute zones,
# etc.) can be added in one place.


func emit(world_pos: Vector2, magnitude: float) -> void:
	var nf := get_tree().get_first_node_in_group("noise_field")
	if nf != null:
		nf.add_noise(world_pos, magnitude)
