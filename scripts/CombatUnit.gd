class_name CombatUnit
extends "res://scripts/Unit.gd"

# Combat substrate. Consolidates the targeting / kite / sprite code that was
# copy-pasted across Rifleman / HeavyGunner / Hunter / Brawler / Looter
# (AUDIT M8). Subclasses still own their own _physics_process and _fire_at -
# those are the per-unit asymmetry surface where faction mechanics will hang.
#
# Counter-system seams (DESIGN_MASTER §6.1):
#   damage_type x unit_size matrix + flat armor, applied via resolve_damage().
#   This batch ships with a NEUTRAL matrix (all 1.0, armor=0) and is therefore
#   zero behavior change; the values get tuned in the balance lab.
#
# Determinism (CLAUDE.md / NETCODE.md):
#   - No transcendentals in sim math. atan2 / rad_to_deg appear ONLY in the
#     sprite-direction picker which is render-only - sim never reads it.
#   - Hostility routes through GameState.is_hostile (team-based, AUDIT H4).
#   - Iteration order over get_nodes_in_group is not stable across clients;
#     the targeting loops return nearest-by-distance which is order-independent
#     up to ties. Tie-break by stable id is a netcode-era follow-up.


# ---- Counter system ----------------------------------------------------

enum DamageType { NORMAL, EXPLOSIVE, PIERCING, INCENDIARY, PLAGUE }
enum UnitSize { SMALL, MEDIUM, LARGE }

@export var damage_type: int = DamageType.NORMAL
@export var unit_size: int = UnitSize.MEDIUM
@export var armor: int = 0


# Type x size multiplier. NEUTRAL today (all 1.0); tuned later. Kept static so
# Projectile.gd can route damage through resolve_damage without an instance.
# Returns float so multi-hit / fractional balance is expressible.
static func type_vs_size_mult(_dt: int, _sz: int) -> float:
	return 1.0


# Pinned-order damage resolution per DESIGN_MASTER §6.1:
#   1. Subtract flat armor (floor at 1, so no shot does literal-0).
#   2. Apply size x type multiplier.
#   3. Apply attacker's _combat_damage_mult() (faction-mechanic hook).
# Defensive against attacker/target without the fields (Shamblers, buildings):
# missing damage_type defaults NORMAL, missing unit_size defaults MEDIUM,
# missing armor defaults 0. With the neutral matrix this is a no-op; the
# arithmetic identically matches the prior `int(round(damage))` path.
static func resolve_damage(raw: float, attacker, target) -> int:
	var amount: float = raw
	var target_armor: int = 0
	if target != null and "armor" in target:
		target_armor = int(target.armor)
	amount = max(1.0, amount - float(target_armor))
	var dt: int = DamageType.NORMAL
	if attacker != null and "damage_type" in attacker:
		dt = int(attacker.damage_type)
	var sz: int = UnitSize.MEDIUM
	if target != null and "unit_size" in target:
		sz = int(target.unit_size)
	amount *= type_vs_size_mult(dt, sz)
	if attacker != null and attacker.has_method("_combat_damage_mult"):
		amount *= attacker._combat_damage_mult()
	return int(round(amount))


# ---- Faction-mechanic hooks (defaults to no-op / 1.0) -------------------

# Multiplicative damage tweak from faction mechanics. Suppression, plague,
# rookie panic, doctrine bonuses, etc. attach here so resolve_damage stays
# the single source of truth for combat math.
func _combat_damage_mult() -> float:
	return 1.0


# Multiplicative range tweak. Subclasses read this in fire/threat queries when
# they want a faction mechanic (e.g. Tribal cluster bonus) to expand the
# engagement bubble.
func _combat_range_mult() -> float:
	return 1.0


# Suppression-aware spread multiplier (DESIGN_MASTER §7.1, v1 read site #2).
# Read at the SHOOTER's position so being IN the zone widens YOUR cone -
# it's about your hands shaking, not your target's evasion. Subclasses
# fold this into the spread arg they pass to ProjectileManager. Returns
# 1.0 if the SuppressionField node isn't in the scene (single-unit test
# scenes, etc.). v2 hook: veterancy / doctrine resistance multiplies onto
# the value_at(...) reading inside SuppressionField before the spread
# math, not here.
func _suppression_spread_multiplier() -> float:
	var sf = get_tree().get_first_node_in_group("suppression_field")
	if sf != null and sf.has_method("spread_multiplier_at"):
		return sf.spread_multiplier_at(global_position)
	return 1.0


# Post-damage hook for faction mechanics that fire on DEAL not RESOLVE
# (e.g. Looter salvage-on-kill, plague spread, suppression buildup). Empty
# default; subclasses override.
func _on_deal_damage(_target, _amount: int) -> void:
	pass


# ---- Targeting / hostility helpers --------------------------------------

# Nearest hostile unit in range. Falls back to the nearest opposing HQ when
# no unit is in range so units posted at the enemy base auto-attack the HQ
# for the win condition. Hostility is team-based via GameState.is_hostile
# (AUDIT H4 - the previous faction-equality skip broke Military mirror).
#
# Subclasses override `_should_skip_target` to add unit-specific exclusions
# (Hunter excludes ZOMBIE; that's the design quirk that lives on TOP of the
# helper, not inside it - keep the substrate clean of unit-flavor knowledge).
func _find_nearest_hostile(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		if _should_skip_target(u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	if best != null:
		return best
	return _find_nearest_hostile_hq(range_px)


# Nearest opposing-team HQ. Team derived from our own group: an ai_units
# member sees player_buildings as the opposing pool, vice versa.
func _find_nearest_hostile_hq(range_px: float):
	var enemy_group: String = "player_buildings" if is_in_group("ai_units") else "ai_buildings"
	var best = null
	var best_dist := range_px
	for b in get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(b):
			continue
		if not b.is_in_group("hq"):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d <= best_dist:
			best_dist = d
			best = b
	return best


# Nearest threat (hostile unit OR corpse) for kite scans. Corpses are
# included because a corpse on the ground will rise into a Shambler in
# ~30s; for kite purposes the corpse is already a threat.
func _find_nearest_threat_in_range(range_px: float):
	var best = null
	var best_dist := range_px
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not GameState.is_hostile(self, u):
			continue
		if _should_skip_target(u):
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d <= best_dist:
			best_dist = d
			best = u
	for c in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d <= best_dist:
			best_dist = d
			best = c
	return best


# Default: no targets are skipped (use is_hostile semantics directly).
# Hunter overrides to skip ZOMBIE faction (Tribal design quirk).
func _should_skip_target(_u) -> bool:
	return false


# ---- Morale + Personality (DESIGN_MASTER §5.1, v1) ----------------------
#
# Personality archetype, rolled once at spawn via SimRng. Fixed for the
# unit's life. v1 tunes the morale thresholds below; v2 is the full
# "veterancy dampens personality extremes toward a grizzled-veteran
# baseline" convergence (§5.1 explicitly defers it). Determinism: archetype
# uses SimRng, not bare randf (rule #1); morale ticks use the 5 Hz
# delta-accumulator (rule #2); no transcendentals in the band math.
#
# Subclasses opt in via _morale_enabled(). v1 enables Military Rifleman +
# HeavyGunner only - Brawler/Hunter/Looter keep current behavior bit-exact
# in this commit. The threat behaviors (§5.1 axes: reaction, formation)
# are explicitly v2.

enum Archetype { STEADY, SKITTISH, HOTHEAD, GREEN }
enum MoraleBand { STEADY, SHAKEN, BROKEN }

@export var archetype: int = Archetype.GREEN

var morale: float = 1.0
var _morale_band_cached: int = MoraleBand.STEADY
var _morale_tick_timer: float = 0.0
var _flee_lockout_timer: float = 0.0
# One-shot drains (friendly deaths) accumulate here between ticks so the
# per-tick math stays consolidated inside _tick_morale.
var _morale_pending_drain: float = 0.0

# Tick cadence. Matches other 0.2s polls in this substrate; fixed-tick
# delta accumulator per CLAUDE.md rule #2.
const MORALE_TICK_INTERVAL := 0.2

# Threshold bases (lab placeholders).
const SHAKEN_MORALE_BASE := 0.55
const BROKEN_MORALE_BASE := 0.25

# Recovery rate per second when no drain inputs are active. "Safe = courage
# returns" per the spec.
const MORALE_RECOVERY_PER_SEC := 0.15

# Continuous-drain inputs (sim-state driven, no RNG; each linearly summed).
const HP_LOW_FRACTION := 0.4              # below this hp_frac -> hp drain
const HP_LOW_DRAIN_PER_SEC := 0.12        # scaled by deficit
const SUPPRESSION_DRAIN_THRESHOLD := 0.5  # SuppressionField.value_at trigger
const SUPPRESSION_DRAIN_PER_SEC := 0.20   # scaled by suppression value
const OUTNUMBERED_RADIUS_PX := 6.0 * 32.0  # 6 tiles - close pressure ring
const OUTNUMBERED_THRESHOLD := 4          # zombies in radius before drain starts
const OUTNUMBERED_DRAIN_PER_SEC := 0.08   # per zombie over threshold

# One-shot friendly-death drain. Triggered by Unit._die broadcasting to
# nearby same-team combat units.
const FRIENDLY_DEATH_DRAIN := 0.15

# BROKEN-band controls.
const BROKEN_LOCKOUT_SEC := 2.0       # explicit "briefly ignoring orders" from spec
const FEAR_STEP_SPEED := 30.0         # SHAKEN back-step when no immediate kite threat
const SHAKEN_SPREAD_MULT := 1.5       # widen accuracy cone (telegraphed via shake border)

# Per-archetype profile: threshold multipliers + body-color tint vector.
# SKITTISH > 1.0 means shakes/breaks at HIGHER morale (more fragile, breaks
# earlier in a fight). STEADY < 1.0 means breaks only at very low morale.
# HOTHEAD resists breaking moderately but does NOT fear-step when SHAKEN
# (the "overcommits" interpretation; see _morale_should_fear_step).
# Tint is a per-channel multiplier on body_color, applied once at spawn.
const ARCHETYPE_PROFILES := {
	Archetype.STEADY:   {"shake_mult": 0.70, "break_mult": 0.60, "tint": Vector3(0.92, 0.96, 1.00)},
	Archetype.SKITTISH: {"shake_mult": 1.20, "break_mult": 1.20, "tint": Vector3(1.05, 1.05, 1.05)},
	Archetype.HOTHEAD:  {"shake_mult": 0.85, "break_mult": 0.70, "tint": Vector3(1.10, 0.98, 0.92)},
	Archetype.GREEN:    {"shake_mult": 1.00, "break_mult": 1.00, "tint": Vector3(1.00, 1.00, 1.00)},
}


# Subclasses opt in by overriding. Default off so existing CombatUnit
# subclasses (Brawler / Hunter / Looter) keep their current behavior
# bit-exact this commit. Rifleman + HeavyGunner override to true.
func _morale_enabled() -> bool:
	return false


func _ready() -> void:
	super._ready()
	if _morale_enabled():
		# SimRng (not bare randf) so the spawn archetype roll is reproducible
		# across clients for lockstep multiplayer.
		archetype = SimRng.randi_range(Archetype.STEADY, Archetype.GREEN)
		_apply_archetype_tint()


func _apply_archetype_tint() -> void:
	# Subtle persistent visual tell per archetype (§5.1: "even just a tint /
	# marker so the player can learn 'that one's skittish'"). Per-channel
	# multiplier on body_color clamped to [0..1]. Applied once at spawn.
	var profile: Dictionary = ARCHETYPE_PROFILES[archetype]
	var tint: Vector3 = profile["tint"]
	body_color = Color(
		clamp(body_color.r * tint.x, 0.0, 1.0),
		clamp(body_color.g * tint.y, 0.0, 1.0),
		clamp(body_color.b * tint.z, 0.0, 1.0),
		body_color.a,
	)


# Called by Unit._broadcast_friendly_death when a same-team combat unit
# dies inside the broadcast radius. Queues a one-shot drain consumed on
# the next morale tick (so all morale math stays inside _tick_morale).
func on_friendly_died(_pos: Vector2) -> void:
	if not _morale_enabled():
		return
	_morale_pending_drain += FRIENDLY_DEATH_DRAIN


# Subclass _physics_process calls this once per tick. Returns the cached
# morale band so the subclass can branch on it (kite when SHAKEN, walk to
# flee target when BROKEN). Sim-state-driven; the only RNG was the spawn
# archetype roll above.
func _tick_morale(delta: float) -> int:
	if not _morale_enabled():
		return MoraleBand.STEADY
	_flee_lockout_timer = max(0.0, _flee_lockout_timer - delta)
	_morale_tick_timer -= delta
	if _morale_tick_timer > 0.0:
		return _morale_band_cached
	_morale_tick_timer = MORALE_TICK_INTERVAL
	var prev_band: int = _morale_band_cached
	# Sum continuous-drain inputs. Recovery only fires when total drain is
	# zero (per spec: "recovers over time when none of those are present").
	var drain_per_sec: float = 0.0
	var max_eff: int = get_effective_max_hp()
	if max_eff > 0:
		var hp_frac: float = float(current_hp) / float(max_eff)
		if hp_frac < HP_LOW_FRACTION:
			var hp_deficit: float = (HP_LOW_FRACTION - hp_frac) / HP_LOW_FRACTION
			drain_per_sec += HP_LOW_DRAIN_PER_SEC * hp_deficit
	var sf = get_tree().get_first_node_in_group("suppression_field")
	if sf != null and sf.has_method("value_at"):
		var s: float = sf.value_at(global_position)
		if s >= SUPPRESSION_DRAIN_THRESHOLD:
			drain_per_sec += SUPPRESSION_DRAIN_PER_SEC * s
	var nearby_z: int = _count_nearby_hostile_zombies()
	if nearby_z > OUTNUMBERED_THRESHOLD:
		drain_per_sec += OUTNUMBERED_DRAIN_PER_SEC * float(nearby_z - OUTNUMBERED_THRESHOLD)
	if drain_per_sec > 0.0:
		morale = max(0.0, morale - drain_per_sec * MORALE_TICK_INTERVAL)
	else:
		morale = min(1.0, morale + MORALE_RECOVERY_PER_SEC * MORALE_TICK_INTERVAL)
	if _morale_pending_drain > 0.0:
		morale = max(0.0, morale - _morale_pending_drain)
		_morale_pending_drain = 0.0
	var new_band: int = _compute_band(morale)
	if new_band != prev_band:
		_on_morale_band_changed(prev_band, new_band)
	_morale_band_cached = new_band
	return _morale_band_cached


# Veterancy's v1-lite flat resistance per §5.1: "higher veterancy_level
# adds flat morale resistance (raises the effective morale, resists
# breaking)". Additive bonus on the comparison side, NOT on the raw morale
# value, so the unit still feels the drain - it just survives it longer.
func _veterancy_morale_bonus() -> float:
	return float(max(0, veterancy_level - 1)) * 0.05


func _compute_band(raw_morale: float) -> int:
	var profile: Dictionary = ARCHETYPE_PROFILES[archetype]
	var effective: float = raw_morale + _veterancy_morale_bonus()
	var shake_thresh: float = SHAKEN_MORALE_BASE * float(profile["shake_mult"])
	var break_thresh: float = BROKEN_MORALE_BASE * float(profile["break_mult"])
	if effective <= break_thresh:
		return MoraleBand.BROKEN
	if effective <= shake_thresh:
		return MoraleBand.SHAKEN
	return MoraleBand.STEADY


func _on_morale_band_changed(prev: int, next: int) -> void:
	# Entering BROKEN: take the FLEE branch and route nav to a safe spot.
	# The lockout window (2s) is the explicit "briefly ignoring orders" the
	# spec calls for; the shake-border telegraph in _draw_morale_border
	# warns the player before this fires.
	if next == MoraleBand.BROKEN:
		_flee_lockout_timer = BROKEN_LOCKOUT_SEC
		current_command = Command.FLEE
		_nav.target_position = _flee_target_position()
		MatchStats.log_event(&"morale_broke", {
			"archetype": archetype,
			"veterancy": veterancy_level,
			"morale": morale,
			"pos": [global_position.x, global_position.y],
		})
	elif prev == MoraleBand.BROKEN and next != MoraleBand.BROKEN:
		# Recovered: clear FLEE so the subclass resumes the IDLE/threat path.
		current_command = Command.IDLE
		MatchStats.log_event(&"morale_recovered", {
			"archetype": archetype,
			"veterancy": veterancy_level,
			"morale": morale,
		})


# Count of ZOMBIE-faction hostile units inside the pressure ring. Iterates
# the units group (small ring + 5 Hz cadence keeps it cheap). Routes
# through faction == ZOMBIE rather than is_hostile because only ZOMBIE
# pressure feeds the outnumbered drain (player-vs-player attrition is
# already covered by the friendly-death broadcast + HP-low drain).
func _count_nearby_hostile_zombies() -> int:
	var count: int = 0
	var r_sq: float = OUTNUMBERED_RADIUS_PX * OUTNUMBERED_RADIUS_PX
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if not ("faction" in u) or u.faction != GameState.Faction.ZOMBIE:
			continue
		if global_position.distance_squared_to(u.global_position) <= r_sq:
			count += 1
	return count


# Read-side helpers consumed by subclass _physics_process. Defaults live
# here so non-morale CombatUnit subclasses get sensible no-ops.

func _morale_spread_mult() -> float:
	if _morale_band_cached == MoraleBand.SHAKEN:
		return SHAKEN_SPREAD_MULT
	return 1.0


func _morale_should_fear_step() -> bool:
	if _morale_band_cached != MoraleBand.SHAKEN:
		return false
	# HOTHEAD doesn't fear-step (overcommits, by design). All other
	# archetypes back away while still firing - the readable shake before
	# the break.
	return archetype != Archetype.HOTHEAD


# Nearest own-team building (HQ, Barracks, CP - whatever's intact). Falls
# back to current position if no friendly buildings remain (last-stand
# edge case where flee resolves to "hold ground").
func _flee_target_position() -> Vector2:
	var friendly_group: String = "player_buildings" if is_in_group("player_units") else "ai_buildings"
	var best = null
	var best_dist: float = INF
	for b in get_tree().get_nodes_in_group(friendly_group):
		if not is_instance_valid(b):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best = b
	if best == null:
		return global_position
	return best.position


# Override of Unit.move_to. While BROKEN with the lockout active, refuse
# player MOVE orders - the explicit "briefly ignoring orders" from §5.1.
# Lockout is short (BROKEN_LOCKOUT_SEC = 2s) and the shake-border telegraphs
# the impending break, so the player sees it coming.
func move_to(world_pos: Vector2) -> void:
	if _morale_band_cached == MoraleBand.BROKEN and _flee_lockout_timer > 0.0:
		return
	super.move_to(world_pos)


# Render-side morale telegraph. Called from Unit._draw via has_method
# duck-type so non-CombatUnit subclasses don't need to know about it.
# Yellow border = SHAKEN (early warning); red border = BROKEN. Polyline
# traces the same trapezoid the body uses so the cue sits on the silhouette.
func _draw_morale_border(bw: float, body_top_y: float) -> void:
	if not _morale_enabled():
		return
	var border_color: Color
	if _morale_band_cached == MoraleBand.BROKEN:
		border_color = Color(0.95, 0.30, 0.30, 0.95)
	elif _morale_band_cached == MoraleBand.SHAKEN:
		border_color = Color(0.95, 0.85, 0.30, 0.85)
	else:
		return
	var poly := PackedVector2Array([
		Vector2(-bw * 0.42, body_top_y + 2.0),
		Vector2(bw * 0.42, body_top_y + 2.0),
		Vector2(bw * 0.5, -1.0),
		Vector2(-bw * 0.5, -1.0),
		Vector2(-bw * 0.42, body_top_y + 2.0),
	])
	draw_polyline(poly, border_color, 1.5, false)


# Move directly away from a threat at the given speed. Used by ranged units'
# IDLE-state defensive kite. Uses Vector2.normalized (sqrt only - not a
# transcendental); the gameplay rule "back away when threatened" is fully
# deterministic. move_and_slide is the existing nav/collision path.
func _kite_from(threat, kite_speed: float) -> void:
	var away: Vector2 = global_position - threat.global_position
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	velocity = away.normalized() * kite_speed
	move_and_slide()


# Centralized noise emission for shot/melee sounds. Subclasses pass their
# per-unit magnitude (Rifleman 10, HG 25, Hunter 1, Looter 20, Brawler 0).
# Per CLAUDE.md: every noise emit goes through NoiseBus with a named const.
func _emit_shot_noise(magnitude: float) -> void:
	if magnitude > 0.0:
		NoiseBus.emit(global_position, magnitude)


# ---- Sprite system (parameterized by _get_sprite_root()) ----------------
#
# RENDER ONLY. The atan2 inside _world_facing_to_sprite_dir is sanctioned
# by CLAUDE.md as a render-side transcendental - sim state never reads back
# from the chosen sprite frame.

const SPRITE_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

# Subclasses that have sprites return their root path (e.g.
# "res://assets/sprites/units/military/rifleman/"). Empty string = no sprite,
# procedural body drawing in Unit._draw is used instead.
func _get_sprite_root() -> String:
	return ""


# Animation speeds in fps per action. Subclasses override only if their art
# wants a different cadence (Looter uses slower attack speed for the magnum
# kick; Rifleman defaults).
func _sprite_anim_speeds() -> Dictionary:
	return {"idle": 4.0, "walk": 12.0, "attack": 18.0, "death": 8.0}


# Construct a SpriteFrames resource by probing the on-disk asset tree
# rooted at _get_sprite_root(). Each (action, direction) becomes a named
# animation; we probe sequential frame indices until a missing file ends
# the cycle.
func _build_sprite_frames() -> SpriteFrames:
	var root: String = _get_sprite_root()
	if root == "":
		return null
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	var anim_speeds := _sprite_anim_speeds()
	var anim_loops := {"idle": true, "walk": true, "attack": false, "death": false}
	for action in ["idle", "walk", "attack", "death"]:
		for dir in SPRITE_DIRECTIONS:
			var anim_name := "%s_%s" % [action, dir]
			var added_any := false
			var i := 0
			while true:
				var frame_path := "%s%s/%s/%d.png" % [root, action, dir, i]
				if not ResourceLoader.exists(frame_path):
					break
				if not added_any:
					sf.add_animation(anim_name)
					sf.set_animation_speed(anim_name, anim_speeds[action])
					sf.set_animation_loop(anim_name, anim_loops[action])
					added_any = true
				sf.add_frame(anim_name, load(frame_path))
				i += 1
	return sf


# Pick one of 8 sprite directions from a world facing vector. RENDER ONLY
# (sim does not read sprite_dir). The world->iso projection is the game's
# 4:3 oblique transform; the atan2+rad_to_deg are the sanctioned render-
# side transcendentals per CLAUDE.md.
func _world_facing_to_sprite_dir(world_dir: Vector2) -> String:
	if world_dir.length_squared() < 0.001:
		return "south"
	var iso_dir := Vector2(world_dir.x - world_dir.y, (world_dir.x + world_dir.y) * 0.75)
	var angle_deg := rad_to_deg(iso_dir.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var idx := int(round(angle_deg / 45.0)) % 8
	return SPRITE_DIRECTIONS[idx]


# Subclasses call this from _ready after super._ready() to wire up the
# sprite child (an AnimatedSprite2D node in the scene file). No-op if the
# subclass has no sprite root or no AnimatedSprite2D child.
func _init_sprite() -> void:
	if _get_sprite_root() == "":
		return
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frames := _build_sprite_frames()
	if frames == null or frames.get_animation_names().is_empty():
		return
	sprite.sprite_frames = frames
	use_sprite = true
	sprite.play(&"idle_south")


# Pick the current animation (action + direction) and play it on the sprite
# child. Called by subclasses every physics tick when use_sprite is true.
# attack_anim_timer comes from the subclass and counts down each tick so
# the attack animation visibly plays for a beat after firing.
var _attack_anim_timer: float = 0.0

func _update_sprite_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String
	if current_hp <= 0:
		action = "death"
	elif _attack_anim_timer > 0.0:
		action = "attack"
	elif velocity.length_squared() > 1.0 or current_command == Command.MOVE:
		action = "walk"
	else:
		action = "idle"
	var dir: String = _world_facing_to_sprite_dir(facing_dir)
	var anim_name := "%s_%s" % [action, dir]
	if String(sprite.animation) != anim_name:
		sprite.play(anim_name)
