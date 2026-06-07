extends Node2D

const NOISE_DECAY_RATE := 10.0
const REACH_PER_NOISE := 2.0
const MAX_REACH := 480.0
const MERGE_RADIUS := 96.0
const MIN_INTENSITY := 1.0
const ATTRACT_INTERVAL := 0.4
const MAP_SIZE := Vector2(6144, 6144)
const SHAMBLER_SCENE := preload("res://scenes/units/Shambler.tscn")
# H14: derive occluder cache radius from Shambler's hearing range so the two
# can't drift apart again (they did once - hearing was bumped 512 -> 704 px
# but the cache stayed at 512 + 100, so distant zombies heard through walls).
const ShamblerScript := preload("res://scripts/Shambler.gd")
# Building occlusion. Each building between an emitter and a hearer multiplies
# the effective intensity by this factor. Two buildings between -> 0.25x.
# Integrates with the Survivor "engineered position" identity: firing from
# within claimed buildings produces less zombie attention than firing outside.
const BUILDING_NOISE_DAMP := 0.5
# Per-emitter occluder cache radius. Hearers (zombies) cap at HEARING_RANGE_PX
# from the emitter; buildings beyond emitter_pos + cache radius can't intersect
# any emitter-to-hearer segment. Margin accounts for buildings whose center is
# just beyond range but whose corner reaches into a segment. Used to pre-filter
# buildings on emitter creation so _attenuated_intensity iterates a 2-5 entry
# list instead of all ~95.
const OCCLUDER_CACHE_MARGIN_PX := 100.0
const OCCLUDER_CACHE_RADIUS_PX := ShamblerScript.HEARING_RANGE_PX + OCCLUDER_CACHE_MARGIN_PX

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

const HORDE_COOLDOWN := 30.0
const WAVE_SIZE_MULTIPLIER := 0.5
const MAX_WAVE := 4
const MAX_ZOMBIE_POPULATION := 300  # refuse horde spawns when total zombies reach this (bumped from 220 after Shambler perception perf fixes)


class Emitter:
	var position: Vector2
	var intensity: float = 0.0
	var tiers_fired: Array = [false, false, false, false]
	# Precomputed list of buildings near enough to this emitter that they
	# could occlude noise from it. Set once on emitter creation by
	# NoiseField._populate_occluder_cache. Iterated by _attenuated_intensity
	# instead of the full buildings group.
	var occluder_candidates: Array = []

	func _init(p: Vector2, m: float) -> void:
		position = p
		intensity = m


var _emitters: Array = []
var _debug_visible := false
var _attract_timer := 0.0
var _debug_font: Font
var _last_horde_time: float = -1000.0
var _wave_count: int = 0

# Perf instrumentation. _last_attract_us is the duration of the most recent
# _attract_zombies call in microseconds. _last_occlusion_us is the cumulative
# time spent inside _attenuated_intensity during that same call. PerfProbe
# reads both to surface the cost in its 30s probes.
var _last_attract_us: int = 0
var _last_occlusion_us: int = 0
var _occlusion_calls_last_tick: int = 0
# Runtime flag toggled by --no-occlusion CLI arg. When false, _attenuated_intensity
# is a no-op (returns base unchanged) so the user can A/B test the impact of
# the occlusion check during a single playtest.
var _occlusion_enabled: bool = true


func _ready() -> void:
	add_to_group("noise_field")
	_debug_font = ThemeDB.fallback_font
	# --no-occlusion CLI flag disables building occlusion for A/B testing.
	if "--no-occlusion" in OS.get_cmdline_user_args():
		_occlusion_enabled = false
		print("[NoiseField] Building occlusion DISABLED via --no-occlusion flag")


func add_noise(world_pos: Vector2, magnitude: float) -> void:
	# Phase 2.5: every noise event deposits residue on ZombieField's grid,
	# producing slow persistent attraction to combat areas even after the
	# immediate horde response has passed. Residue decays exponentially
	# (2%/sec) so quiet shots fade in ~30 sec; sustained heavy fire keeps
	# pulling ambient zombies in for 2-3 min.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("deposit_residue"):
		zf.deposit_residue(world_pos, magnitude)
	for e in _emitters:
		if e.position.distance_to(world_pos) <= MERGE_RADIUS:
			var total: float = e.intensity + magnitude
			if total > 0.0:
				e.position = (e.position * e.intensity + world_pos * magnitude) / total
			e.intensity = total
			# Merge can shift position by up to MERGE_RADIUS (96 px). Against
			# a cache radius derived from hearing range (~800 px) the shift is
			# negligible; cache stays.
			return
	var new_emitter := Emitter.new(world_pos, magnitude)
	_populate_occluder_cache(new_emitter)
	_emitters.append(new_emitter)


func _populate_occluder_cache(emitter) -> void:
	# Filter buildings to those within OCCLUDER_CACHE_RADIUS_PX of the emitter
	# position. Run once per emitter creation. Cost: O(buildings) once instead
	# of O(buildings) per (zombie, emitter) pair at 2.5 Hz.
	var cache_rad_sq: float = OCCLUDER_CACHE_RADIUS_PX * OCCLUDER_CACHE_RADIUS_PX
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or not ("size_pixels" in b):
			continue
		if emitter.position.distance_squared_to(b.position) <= cache_rad_sq:
			emitter.occluder_candidates.append(b)


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

		if e.intensity < SMALL_THRESHOLD:
			e.tiers_fired = [false, false, false, false]

		# H5: only consume the tier flag when the horde *actually* fires. Pre-fix
		# the flag was set before _maybe_trigger_horde checked cooldown / pop
		# cap, so sustained heavy fire during cooldown left tiers_fired armed
		# with no horde ever spawning - undermining the HG-anxiety thesis.
		if e.intensity >= CATASTROPHIC_THRESHOLD and not e.tiers_fired[TIER_CAT]:
			if _maybe_trigger_horde(e.position, CATASTROPHIC_SIZE, "catastrophic"):
				e.tiers_fired[TIER_CAT] = true
		elif e.intensity >= LARGE_THRESHOLD and not e.tiers_fired[TIER_LARGE]:
			if _maybe_trigger_horde(e.position, LARGE_SIZE, "large"):
				e.tiers_fired[TIER_LARGE] = true
		elif e.intensity >= MEDIUM_THRESHOLD and not e.tiers_fired[TIER_MEDIUM]:
			if _maybe_trigger_horde(e.position, MEDIUM_SIZE, "medium"):
				e.tiers_fired[TIER_MEDIUM] = true
		elif e.intensity >= SMALL_THRESHOLD and not e.tiers_fired[TIER_SMALL]:
			if _maybe_trigger_horde(e.position, SMALL_SIZE, "small"):
				e.tiers_fired[TIER_SMALL] = true

		if e.intensity < MIN_INTENSITY:
			to_remove.append(i)

	to_remove.reverse()
	for i in to_remove:
		_emitters.remove_at(i)

	# Earned silence: when all noise sources fade, reset the wave count.
	if _emitters.is_empty() and _wave_count > 0:
		_wave_count = 0

	_attract_timer -= delta
	if _attract_timer <= 0.0:
		_attract_timer = ATTRACT_INTERVAL
		_attract_zombies()

	if _debug_visible:
		queue_redraw()


func _maybe_trigger_horde(pos: Vector2, base_size: int, tier_label: String) -> bool:
	# Returns true iff a horde actually spawned. The caller (per-tier check in
	# _process) only marks tiers_fired on a true return so a suppressed horde
	# can re-trigger once cooldown/pop-cap allow it. See H5.
	var now: float = Time.get_ticks_msec() / 1000.0
	var time_since_last: float = now - _last_horde_time
	if time_since_last < HORDE_COOLDOWN:
		print("[NoiseField] %s horde suppressed (cooldown %.1fs remaining)" % [tier_label, HORDE_COOLDOWN - time_since_last])
		MatchStats.log_event(&"horde_suppressed", {
			"tier": tier_label,
			"reason": "cooldown",
			"cooldown_remaining": HORDE_COOLDOWN - time_since_last,
		})
		return false
	# Population cap - stops the horde-spawn loop from snowballing once
	# enough zombies are alive to make further spawns redundant for
	# difficulty AND expensive for the frame budget.
	var zf = get_tree().get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombie_count"):
		var current_pop: int = zf.get_zombie_count()
		if current_pop >= MAX_ZOMBIE_POPULATION:
			print("[NoiseField] %s horde suppressed (population cap %d/%d)" % [tier_label, current_pop, MAX_ZOMBIE_POPULATION])
			MatchStats.log_event(&"horde_suppressed", {
				"tier": tier_label,
				"reason": "pop_cap",
				"pop": current_pop,
			})
			return false
	_last_horde_time = now
	var size_mult: float = 1.0 + float(min(_wave_count, MAX_WAVE)) * WAVE_SIZE_MULTIPLIER
	var actual_size: int = int(round(base_size * size_mult))
	print("[NoiseField] %s horde fires: wave %d, %d Shamblers (base %d x %.1f)" % [tier_label, _wave_count + 1, actual_size, base_size, size_mult])
	_wave_count += 1
	MatchStats.log_event(&"horde_fired", {
		"tier": tier_label,
		"size": actual_size,
		"target": [pos.x, pos.y],
		"wave_num": _wave_count,
	})
	_trigger_horde(pos, actual_size)
	return true


func _attract_zombies() -> void:
	# Two paths:
	#   hear_noise(pos, magnitude, distance) - new perception API. Zombie
	#     filters by its own hearing range and attenuation; we just deliver
	#     every emitter so the zombie can decide what it hears.
	#   investigate(pos)                     - legacy path for zombie types
	#     not yet migrated to the perception system; uses emitter reach.
	var t0_us: int = Time.get_ticks_usec()
	_last_occlusion_us = 0
	_occlusion_calls_last_tick = 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if u.faction != 2:
			continue
		if u.has_method("hear_noise"):
			for e in _emitters:
				var d: float = u.global_position.distance_to(e.position)
				# H12: skip the occluder-loop math for pairs the hearer is going
				# to discard anyway. hear_noise's first line is the same range
				# check; running it here avoids _attenuated_intensity entirely
				# for the (population - in_range_count) majority of pairs.
				if d > ShamblerScript.HEARING_RANGE_PX:
					continue
				var eff: float = _attenuated_intensity(e, u.global_position, e.intensity)
				u.hear_noise(e.position, eff, d)
		elif u.has_method("investigate"):
			var best_emitter = null
			var best_intensity: float = 0.0
			for e in _emitters:
				var eff: float = _attenuated_intensity(e, u.global_position, e.intensity)
				var reach: float = min(eff * REACH_PER_NOISE, MAX_REACH)
				var d: float = u.global_position.distance_to(e.position)
				if d <= reach and eff > best_intensity:
					best_intensity = eff
					best_emitter = e
			if best_emitter != null:
				u.investigate(best_emitter.position)
	_last_attract_us = Time.get_ticks_usec() - t0_us


func _attenuated_intensity(emitter, hearer_pos: Vector2, base: float) -> float:
	if not _occlusion_enabled:
		return base
	var t0_us: int = Time.get_ticks_usec()
	var result: float = _attenuated_intensity_inner(emitter, hearer_pos, base)
	_last_occlusion_us += Time.get_ticks_usec() - t0_us
	_occlusion_calls_last_tick += 1
	return result


func _attenuated_intensity_inner(emitter, hearer_pos: Vector2, base: float) -> float:
	# Iterate the per-emitter occluder candidate list (precomputed on emitter
	# creation - buildings within OCCLUDER_CACHE_RADIUS_PX of the emitter).
	# Typical candidate count: 2-5. Previously this iterated the full ~95
	# building group per (emitter, hearer) pair at 2.5 Hz - the dominant
	# 5-minute degradation cost. Bounding-rect early-out + 4-segment test
	# unchanged otherwise.
	var emitter_pos: Vector2 = emitter.position
	var seg_rect := Rect2(
		Vector2(min(emitter_pos.x, hearer_pos.x), min(emitter_pos.y, hearer_pos.y)),
		Vector2(abs(emitter_pos.x - hearer_pos.x) + 1.0, abs(emitter_pos.y - hearer_pos.y) + 1.0),
	)
	var occluders: int = 0
	for b in emitter.occluder_candidates:
		# is_instance_valid filters buildings that were destroyed after the
		# cache was built. Cheap; cache stays accurate without invalidation.
		if not is_instance_valid(b) or not ("size_pixels" in b):
			continue
		var half: Vector2 = b.size_pixels * 0.5
		var rect := Rect2(b.position - half, b.size_pixels)
		if not seg_rect.intersects(rect):
			continue
		if _segment_intersects_rect(emitter_pos, hearer_pos, rect):
			occluders += 1
	if occluders == 0:
		return base
	return base * pow(BUILDING_NOISE_DAMP, float(occluders))


func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var tl := rect.position
	var tr := Vector2(rect.position.x + rect.size.x, rect.position.y)
	var bl := Vector2(rect.position.x, rect.position.y + rect.size.y)
	var br := rect.position + rect.size
	return (
		Geometry2D.segment_intersects_segment(a, b, tl, tr) != null
		or Geometry2D.segment_intersects_segment(a, b, tr, br) != null
		or Geometry2D.segment_intersects_segment(a, b, br, bl) != null
		or Geometry2D.segment_intersects_segment(a, b, bl, tl) != null
	)


func _trigger_horde(target: Vector2, size: int) -> void:
	var spawn_pos := _pick_edge_spawn(target)
	for i in range(size):
		# Routed through SimRng (per CLAUDE.md Determinism Rule #1) so future
		# replay/lockstep matches stage the same hordes deterministically.
		var jitter := Vector2(SimRng.randf_range(-60, 60), SimRng.randf_range(-60, 60))
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
	var now: float = Time.get_ticks_msec() / 1000.0
	var cooldown_remaining: float = max(0.0, HORDE_COOLDOWN - (now - _last_horde_time))
	for e in _emitters:
		var reach: float = min(e.intensity * REACH_PER_NOISE, MAX_REACH)
		var ratio: float = clamp(e.intensity / SMALL_THRESHOLD, 0.0, 1.0)
		# Project emitter world position to iso for debug visualization. Reach
		# stays in screen pixels - a circle of "reach" at iso center is a useful
		# debug halo even if it's not strictly the iso-projection of a world circle
		# (which would be a 4:3 ellipse).
		var iso_pos: Vector2 = IsoView.world_to_screen(e.position)
		draw_circle(iso_pos, reach, Color(1, 0.4, 0.1, 0.13), true, -1, true)
		var ring_alpha: float = 0.45 + 0.5 * ratio
		draw_arc(iso_pos, reach, 0.0, TAU, 56, Color(1, 0.4, 0.1, ring_alpha), 2.5, true)
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
			var status := "%d%s" % [int(e.intensity), tier_label]
			if cooldown_remaining > 0.0:
				status += " | CD %.0fs" % cooldown_remaining
			if _wave_count > 0:
				status += " | W%d" % _wave_count
			draw_string(_debug_font, iso_pos + Vector2(-32, -reach - 6), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6, 0.95))
