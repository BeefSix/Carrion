extends Node2D

const NOISE_DECAY_RATE := 5.0
const REACH_PER_NOISE := 2.0
const MERGE_RADIUS := 96.0
const HORDE_THRESHOLD := 200.0
const HORDE_SIZE := 15
const HORDE_COOLDOWN := 3.0
const MIN_INTENSITY := 1.0
const ATTRACT_INTERVAL := 0.4
const MAP_SIZE := Vector2(2560, 2560)
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")


class Emitter:
	var position: Vector2
	var intensity: float = 0.0
	var horde_cooldown: float = 0.0

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
		e.horde_cooldown = max(0.0, e.horde_cooldown - delta)
		if e.intensity >= HORDE_THRESHOLD and e.horde_cooldown <= 0.0:
			_trigger_horde(e.position)
			e.intensity = 0.0
			e.horde_cooldown = HORDE_COOLDOWN
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
		if u.faction != 2:  # Faction.ZOMBIE = 2
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


func _trigger_horde(target: Vector2) -> void:
	var spawn_pos := _pick_edge_spawn(target)
	for i in range(HORDE_SIZE):
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
		var ratio: float = clamp(e.intensity / HORDE_THRESHOLD, 0.0, 1.0)
		draw_circle(e.position, reach, Color(1, 0.4, 0.1, 0.13), true, -1, true)
		var ring_alpha: float = 0.45 + 0.5 * ratio
		draw_arc(e.position, reach, 0.0, TAU, 56, Color(1, 0.4, 0.1, ring_alpha), 2.5, true)
		if _debug_font != null:
			var label := "%d" % int(e.intensity)
			draw_string(_debug_font, e.position + Vector2(-12, -reach - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6, 0.95))
