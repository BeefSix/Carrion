extends "res://scripts/CombatUnit.gd"

const ATTACK_RANGE := 224.0
const ATTACK_DAMAGE := 14
const ATTACK_PERIOD := 1.0
const NOISE_PER_SHOT := 1.0
const RETARGET_INTERVAL := 0.3
const KITE_RANGE := 100.0
const KITE_SPEED := 30.0

# Projectile config: dark organic-toned arrow per Tribal faction identity.
# Slower than Military per the design doc's 0.4-0.7s arrow flight target.
const PROJECTILE_SPEED := 500.0
const PROJECTILE_COLOR := Color(0.45, 0.35, 0.22)
# Tighter cone than Rifleman: Hunter is a deliberate aimed shooter.
const BASE_ACCURACY_DEG := 3.0

# Thrall escort (DESIGN_MASTER §7.2 living-armor, redesigned 2026-06-09).
# The clicking-as-area-noise version failed its feel-test: NoiseField
# deposits triggered hordes and pulled 50+ zombies map-wide, making the
# Hunter an army-summoner (that's the Shaman's role). Replaced with a
# BOUNDED recruiter: the Hunter claims up to MAX_THRALLS nearby wild
# zombies as a purely defensive escort. Thralls body-block threats and
# absorb hits but contribute ZERO offense — the escort raises the
# Hunter's survivability, never his killing power. Concentrated ranged
# fire still reaches the Hunter past the escort (the Military counter).
# Recruiting is direct assignment (no NoiseField, no noise event at all):
# nearest unowned wild zombie within recruit range, checked on a fixed
# interval, only while below the cap.
const MAX_THRALLS := 4                    # placeholder — lab-tunable
const THRALL_RECRUIT_RADIUS_PX := 128.0   # ~4 tiles; local pull only
const THRALL_RECRUIT_INTERVAL := 1.0      # sim seconds between recruit attempts

# Sprite wiring (render-only, CombatUnit substrate helpers).
const SPRITE_ROOT := "res://assets/sprites/units/tribal/hunter/"
const ATTACK_ANIM_HOLD := 0.5

var _target = null
var _attack_cooldown := 0.0
var _retarget_timer := 0.0


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _ready() -> void:
	super._ready()
	_init_sprite()
var _thralls: Array = []                  # owned Shamblers; pruned each attempt
var _recruit_timer: float = 0.0
# Threat-scan cache - 5Hz polling instead of per-frame.
const THREAT_CHECK_INTERVAL := 0.2
var _threat_check_timer: float = 0.0
var _threat_cached = null


# Opt in to morale + personality (CombatUnit §5.1). DESIGN_MASTER says every
# unit has morale + personality + reaction; v1 enabled it on Military
# combat units (Rifleman + HeavyGunner). Tribal Hunter joins them here.
# Counter-seam fields (damage_type / unit_size / armor) inherit CombatUnit's
# neutral defaults per NETCODE.md Decision #2.
func _morale_enabled() -> bool:
	return true


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	# Thrall recruiting — fixed-interval accumulator on the physics tick.
	# Runs in every command state (recruiting is passive identity), but
	# only attempts while below the cap. No RNG, no NoiseField.
	_recruit_timer += delta
	if _recruit_timer >= THRALL_RECRUIT_INTERVAL:
		_recruit_timer = 0.0
		_try_recruit_thrall()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		elif stance == Stance.AGGRESSIVE:
			_try_shoot_in_range(delta)
		return

	if stance == Stance.PASSIVE:
		velocity = Vector2.ZERO
		return

	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null:
		_kite_from(threat, KITE_SPEED)
	else:
		velocity = Vector2.ZERO

	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile(ATTACK_RANGE)
	if _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
			_fire_at(_target)
			_attack_cooldown = ATTACK_PERIOD
			_emit_shot_noise(NOISE_PER_SHOT)


func _try_shoot_in_range(delta: float) -> void:
	# Attack-while-moving: keep the nav target, fire opportunistically at any
	# hostile (humans only - the _should_skip_target override below excludes
	# ZOMBIE faction).
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_target = _find_nearest_hostile(ATTACK_RANGE)
	if _target == null or not is_instance_valid(_target):
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0:
		_fire_at(_target)
		_attack_cooldown = ATTACK_PERIOD
		_emit_shot_noise(NOISE_PER_SHOT)


func _fire_at(target) -> void:
	# Damage resolves at impact via CombatUnit.resolve_damage in Projectile.gd.
	# Suppression widens the cone at the shooter's position (DESIGN_MASTER §7.1).
	_attack_anim_timer = ATTACK_ANIM_HOLD  # render-only: hold the bow-draw pose
	var spread: float = BASE_ACCURACY_DEG * (1.0 - squad_accuracy_bonus) * _suppression_spread_multiplier()
	ProjectileManager.spawn_projectile({
		"origin": global_position,
		"target_pos": target.global_position,
		"target": target,
		"damage": float(get_effective_damage(ATTACK_DAMAGE)),
		"speed": PROJECTILE_SPEED,
		"firer": self,
		"faction": faction,
		"spread_deg": spread,
		"style": Projectile.Style.ARROW,
		"color": PROJECTILE_COLOR,
		"visual_length": 16.0,
		"visual_width": 1.8,
	})


# Tribal Hunters fight survivors and military, NOT zombies. The substrate's
# _find_nearest_hostile / _find_nearest_threat_in_range route through this
# hook so the zombie-exemption Tribal-design quirk lives in ONE place on
# top of the shared targeting/threat logic.
func _should_skip_target(u) -> bool:
	return u != null and "faction" in u and u.faction == GameState.Faction.ZOMBIE


func _try_recruit_thrall() -> void:
	# Prune dead/freed thralls first — a death frees the slot and recruiting
	# resumes naturally on the next interval.
	var alive: Array = []
	for t in _thralls:
		if t != null and is_instance_valid(t) and t.thrall_owner == self:
			alive.append(t)
	_thralls = alive
	if _thralls.size() >= MAX_THRALLS:
		return
	# Nearest unowned WILD zombie within recruit range. Deterministic:
	# strict nearest-by-distance, first-seen wins exact ties (group order;
	# acceptable until spawn-ordinal ids land). Tribal-aligned zombies
	# (Shaman force-spawns) are excluded — the Shaman's troops are not
	# the Hunter's to poach, keeps the two roles distinct.
	var best = null
	var best_dist: float = THRALL_RECRUIT_RADIUS_PX
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z):
			continue
		if not ("thrall_owner" in z) or z.thrall_owner != null:
			continue
		if "is_tribal_aligned" in z and z.is_tribal_aligned:
			continue
		# Variants refuse thralldom (make_thrall also guards) — skip them in
		# the scan so a nearby Brute can't shadow a recruitable Shambler.
		if "variant" in z and z.variant != z.VARIANT_SHAMBLER:
			continue
		var d: float = global_position.distance_to(z.global_position)
		if d < best_dist:
			best_dist = d
			best = z
	if best != null and best.has_method("make_thrall"):
		if best.make_thrall(self):
			_thralls.append(best)
