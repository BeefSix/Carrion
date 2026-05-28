extends Node2D

const NOISE_DECAY_RATE := 10.0
const REACH_PER_NOISE := 2.0
const MERGE_RADIUS := 96.0
const MIN_INTENSITY := 1.0
const ATTRACT_INTERVAL := 0.4
const MAP_SIZE := Vector2(2560, 2560)
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")

const SMALL_THRESHOLD := 150.0
const MEDIUM_THRESHOLD := 400.0
const LARGE_THRESHOLD := 800.0
const CATASTROPHIC_THRESHOLD := 1600.0
const SMALL_SIZE := 10
const MEDIUM_SIZE := 25
const LARGE_SIZE := 50
const CATASTROPHIC_SIZE := 75

const TIER_SMALL := 0
const TIER_MEDIUM := 1
const TIER_LARGE := 2
const TIER_CAT := 3


class Emitter:
	var position: Vector2
	var intensity: float = 0.0
	var tiers_fired: Array = [false, false, false, false]

	func _init(p: Vector2, m: float) -> void:
		position = p
		intensity = m


var _emitters: Array = []
var _debug_visible := false
var _attract_timer := 0.0
var _debug_font: Font


func _ready() -> void:
	add_to_group("noise_field")
	_debug_font = ThemeDB.fallback_font


func add_noise(world_pos: Vector2, magnitude: float) -> void:
	for e in _emitters:
		if e.position.distance_to(world_pos) <= MERGE_RADIUS:
			var total: float = e.intensity + magnitude
			if total > 0.0:
				e.position = (e.position * e.intensity + world_pos * magnitude) / total
			e.intensity = total
			return
	_emitters.append(Emitter.new(world_pos, magnitude))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		_debug_visible = not _debug_visible
		queue_redraw()


func _process(delta: float) -> void:
	var decay: float = NOISE_DECAY_RATE * delta
	var to_remove: Array = []
	for i in range(_emitters.size()):
		var e = _emitters[i]
		e.intensity = max(0.0, e.intensity - decay)

		# When intensity falls below the lowest threshold, allow the tiers to re-arm.
		if e.intensity < SMALL_THRESHOLD:
			e.tiers_fired = [false, false, false, false]

		# Fire whichever highest unfired tier the intensity has reached.
		if e.intensity >= CATASTROPHIC_THRESHOLD and not e.tiers_fired[TIER_CAT]:
			e.tiers_fired[TIER_CAT] = true
			_trigger_horde(e.position, CATASTROPHIC_SIZE)
		elif e.intensity >= LARGE_THRESHOLD and not e.tiers_fired[TIER_LARGE]:
			e.tiers_fired[TIER_LARGE] = true
			_trigger_horde(e.position, LARGE_SIZE)
		elif e.intensity >= MEDIUM_THRESHOLD and not e.tiers_fired[TIER_MEDIUM]:
			e.tiers_fired[TIER_MEDIUM] = true
			_trigger_horde(e.position, MEDIUM_SIZE)
		elif e.intensity >= SMALL_THRESHOLD and not e.tiers_fired[TIER_SMALL]:
			e.tiers_fired[TIER_SMALL] = true
			_trigger_horde(e.position, SMALL_SIZE)

		if e.intensity < MIN_INTENSITY:
			to_remove.append(i)

	to_remove.reverse()
	for i in to_remove:
		_emitters.remove_at(i)

	_attract_timer -= delta
	if _attract_timer <= 0.0:
		_attract_timer = ATTRACT_INTERVAL
		_attract_zombies()

	if _debug_visible:
		queue_redraw()


func _attract_zombies() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if u.faction != 2:
			continue
		if not u.has_method("investigate"):
			continue
		var best_emitter = null
		var best_intensity: float = 0.0
		for e in _emitters:
			var reach: float = e.intensity * REACH_PER_NOISE
			var d: float = u.global_position.distance_to(e.position)
			if d <= reach and e.intensity > best_intensity:
				best_intensity = e.intensity
				best_emitter = e
		if best_emitter != null:
			u.investigate(best_emitter.position)


func _trigger_horde(target: Vector2, size: int) -> void:
	var spawn_pos := _pick_edge_spawn(target)
	for i in range(size):
		var jitter := Vector2(randf_range(-60, 60), randf_range(-60, 60))
		var s = SHAMBLER_SCENE.instantiate()
		s.position = spawn_pos + jitter
		get_parent().add_child(s)
		if s.has_method("investigate"):
			s.investigate(target)


func _pick_edge_spawn(target: Vector2) -> Vector2:
	var candidates := [
		Vector2(20.0, target.y),
		Vector2(MAP_SIZE.x - 20.0, target.y),
		Vector2(target.x, 20.0),
		Vector2(target.x, MAP_SIZE.y - 20.0),
	]
	var best: Vector2 = candidates[0]
	var best_dist := INF
	for c in candidates:
		var d: float = c.distance_to(target)
		if d < best_dist:
			best_dist = d
			best = c
	return best


func _draw() -> void:
	if not _debug_visible:
		return
	for e in _emitters:
		var reach: float = e.intensity * REACH_PER_NOISE
		var ratio: float = clamp(e.intensity / SMALL_THRESHOLD, 0.0, 1.0)
		draw_circle(e.position, reach, Color(1, 0.4, 0.1, 0.13), true, -1, true)
		var ring_alpha: float = 0.45 + 0.5 * ratio
		draw_arc(e.position, reach, 0.0, TAU, 56, Color(1, 0.4, 0.1, ring_alpha), 2.5, true)
		if _debug_font != null:
			var tier_label := ""
			if e.intensity >= CATASTROPHIC_THRESHOLD:
				tier_label = " CAT"
			elif e.intensity >= LARGE_THRESHOLD:
				tier_label = " LRG"
			elif e.intensity >= MEDIUM_THRESHOLD:
				tier_label = " MED"
			elif e.intensity >= SMALL_THRESHOLD:
				tier_label = " SML"
			var label := "%d%s" % [int(e.intensity), tier_label]
			draw_string(_debug_font, e.position + Vector2(-16, -reach - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6, 0.95))
