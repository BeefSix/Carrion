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
