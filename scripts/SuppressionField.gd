extends Node2D

# Suppression field (DESIGN_MASTER §7.1). A short-lived, decaying scalar field
# fed by ranged-projectile impacts. Read by position to scale movement speed
# and projectile spread on any unit standing in a suppressed zone.
#
# Universal source, volume-gated: every ranged impact deposits the same flat
# amount, but the per-hit deposit + linear decay are tuned so one shooter's
# deposits decay before crossing the saturation line. Concentrated/sustained
# fire from multiple shooters on one area builds a zone - Military's massed
# weapons dominate the field by playstyle, not by faction rule. Tribal's
# Hunter and Survivor's crossbow barely register. Melee doesn't deposit (v1).
#
# Architecture mirrors NoiseField (decaying source list + position-weighted
# merge); decay runs on the physics tick per CLAUDE.md Rule #2. No
# transcendentals; distance / sqrt are fine per Rule 5.
#
# All numeric constants are PLACEHOLDERS bound for the balance lab. Named
# clearly so the lab can sweep them in isolation.


# ---- Tuning placeholders (lab targets) ---------------------------------

# Per-impact deposit. Sized so one Rifleman (~1 hit/sec) cannot sustain a
# source above the saturation line: peak intensity = SUPPRESSION_PER_HIT
# (decay clears the previous one between shots), and peak / FULL_SUPPRESSION
# stays below 1.0 -> never fully suppressed by a single shooter.
const SUPPRESSION_PER_HIT := 0.5

# Linear decay per sim second. Spec target: "full clear ~1.5s after last
# deposit". Sustained massed fire can stack intensity well above
# FULL_SUPPRESSION (4 hits/sec at 0.5 ea = 2.0/sec deposit), so DECAY_RATE
# is set so that even a stacked 2.0-intensity source decays inside the
# 1.5s target: 2.0 / 1.5s ≈ 1.33. Round up to 1.5 for a small safety
# margin so the visible zone never lingers past the design window.
const DECAY_RATE := 1.5

# Sources within this radius merge into one (position-weighted by intensity).
# Bounds the source list under sustained massed fire on the same point.
const MERGE_RADIUS := 64.0

# Intensity at which value_at() saturates to 1.0. Pick so:
#   - 1 Rifleman peak ~ 0.5 -> value_at = 0.33 (below threshold)
#   - 3-4 Riflemen sustained -> source -> saturation (full slow + spread)
const FULL_SUPPRESSION := 1.5

# Sources below this drop off the list (housekeeping; no observable
# gameplay effect at this threshold).
const MIN_INTENSITY := 0.01

# Read-side penalty placeholders. Both linear in value_at(). At s = 1.0
# (saturated):
#   speed multiplier = 1 - SUPPRESS_SPEED_PENALTY     -> ~0.5x  (50% slow)
#   spread multiplier = 1 + SUPPRESS_SPREAD_PENALTY   -> ~2.5x  (wider cone)
const SUPPRESS_SPEED_PENALTY := 0.5
const SUPPRESS_SPREAD_PENALTY := 1.5

# Sample radius for value_at: sources within this distance contribute. A
# bit larger than MERGE_RADIUS so the zone has a visible "edge" the eye
# can track on the debug overlay.
const SAMPLE_RADIUS := 96.0

# Debug overlay toggle. F2/F3/F4 are taken (DEV_SPEED / noise inject /
# NoiseField overlay); F5 is free.
const DEBUG_TOGGLE_KEY := KEY_F5


# Internal source record. position drifts with merges (position-weighted),
# intensity is the cumulative deposit minus decay.
class Source:
	var position: Vector2
	var intensity: float = 0.0

	func _init(p: Vector2, m: float) -> void:
		position = p
		intensity = m


var _sources: Array = []
var _debug_visible: bool = false
var _debug_font: Font


func _ready() -> void:
	add_to_group("suppression_field")
	_debug_font = ThemeDB.fallback_font


# Deposit at an impact point. Faction-agnostic: any ranged projectile that
# lands calls this. Merges into the nearest existing source within
# MERGE_RADIUS (intensity-weighted position drift), otherwise appends a new
# source. Magnitudes <= 0 are no-ops.
func deposit(world_pos: Vector2, magnitude: float) -> void:
	if magnitude <= 0.0:
		return
	for s in _sources:
		if s.position.distance_to(world_pos) <= MERGE_RADIUS:
			var total: float = s.intensity + magnitude
			if total > 0.0:
				s.position = (s.position * s.intensity + world_pos * magnitude) / total
			s.intensity = total
			return
	_sources.append(Source.new(world_pos, magnitude))


# Convenience for Projectile.gd: deposits SUPPRESSION_PER_HIT so the per-hit
# constant stays in this file (the only call site for the impact path).
func deposit_hit(world_pos: Vector2) -> void:
	deposit(world_pos, SUPPRESSION_PER_HIT)


# Normalized 0..1 suppression at a world position. Sums every source within
# SAMPLE_RADIUS, clamped to FULL_SUPPRESSION. 0.0 = clear, 1.0 = saturated.
func value_at(world_pos: Vector2) -> float:
	var sum: float = 0.0
	var r_sq: float = SAMPLE_RADIUS * SAMPLE_RADIUS
	for s in _sources:
		if s.position.distance_squared_to(world_pos) <= r_sq:
			sum += s.intensity
	return clamp(sum / FULL_SUPPRESSION, 0.0, 1.0)


# Helper accessors so the penalty constants live in one file. Callers don't
# need to know SUPPRESS_*_PENALTY; they just multiply by these.
func speed_multiplier_at(world_pos: Vector2) -> float:
	return 1.0 - SUPPRESS_SPEED_PENALTY * value_at(world_pos)


func spread_multiplier_at(world_pos: Vector2) -> float:
	return 1.0 + SUPPRESS_SPREAD_PENALTY * value_at(world_pos)


# Fixed-tick decay (CLAUDE.md Rule #2). _physics_process delta still scales
# with Engine.time_scale (same as _process delta in Godot 4), but the tick
# rate is the locked physics rate, which is what we want for sim cadence.
func _physics_process(delta: float) -> void:
	var d: float = DECAY_RATE * delta
	var to_remove: Array = []
	for i in range(_sources.size()):
		var s = _sources[i]
		s.intensity = max(0.0, s.intensity - d)
		if s.intensity < MIN_INTENSITY:
			to_remove.append(i)
	to_remove.reverse()
	for i in to_remove:
		_sources.remove_at(i)
	if _debug_visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == DEBUG_TOGGLE_KEY:
		_debug_visible = not _debug_visible
		queue_redraw()


func _draw() -> void:
	if not _debug_visible:
		return
	# Same iso-projection style as NoiseField's F4 overlay. Outer ring is
	# the SAMPLE_RADIUS footprint (what value_at sees); inner fill scales
	# with current intensity so decay is visible as the fill shrinks.
	for s in _sources:
		var iso_pos: Vector2 = IsoView.world_to_screen(s.position)
		var ratio: float = clamp(s.intensity / FULL_SUPPRESSION, 0.0, 1.0)
		draw_arc(iso_pos, SAMPLE_RADIUS, 0.0, TAU, 40, Color(0.55, 0.75, 1.0, 0.30), 1.5, true)
		var r: float = max(8.0, SAMPLE_RADIUS * ratio * 0.6)
		draw_circle(iso_pos, r, Color(0.45, 0.65, 1.0, 0.18 + 0.25 * ratio), true, -1, true)
		if _debug_font != null:
			var status := "s=%.2f" % s.intensity
			draw_string(_debug_font, iso_pos + Vector2(-16, -SAMPLE_RADIUS - 6), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 1.0, 0.95))
