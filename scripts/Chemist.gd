extends "res://scripts/CombatUnit.gd"

# Survivor Chemist (DESIGN_MASTER §7.3, v1) — "they don't have medicine,
# they have chemistry." Mechanically the Survivor Medic: slow ambient
# radius healing + the morale-recovery aura (CombatUnit._tick_morale reads
# the "medics" group — the aura is profession-agnostic). Unarmed.
#
# NOT CONNECTED YET (2026-06-10): no producer references Chemist.tscn.
# Doctrines (Apothecary / Caustic corpse-dissolving acid — the silent
# corpse-denial answer, §4 "Caustic denial") are [PROPOSED] — deferred.
# The Caustic hook is the interesting one: it lands where Corpse.gd rise
# logic lives, not here.

const HEAL_RADIUS_PX := 96.0          # 3 tiles — stand IN the squad
const HEAL_PER_TICK := 2              # deliberately slow, §2 healing economy
const HEAL_TICK_INTERVAL := 1.0
const KITE_RANGE := 120.0
const KITE_SPEED := 34.0
const THREAT_CHECK_INTERVAL := 0.2

const SPRITE_ROOT := "res://assets/sprites/units/survivor/chemist/"
const HEAL_ANIM_HOLD := 0.8

var _heal_timer: float = 0.0
var _threat_check_timer: float = 0.0
var _threat_cached = null


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _morale_enabled() -> bool:
	return true


func _ready() -> void:
	super._ready()
	# Generic morale-recovery aura group (see Medic.gd — the group is the
	# mechanic, the profession is the flavor).
	add_to_group("medics")
	_init_sprite()


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	var band: int = _tick_morale(delta)
	# Triage runs in every command state, fixed-interval accumulator.
	_heal_timer += delta
	if _heal_timer >= HEAL_TICK_INTERVAL:
		_heal_timer = 0.0
		_tick_heal()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.FLEE:
		_follow_navigation()
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		return
	# IDLE: unarmed — the only self-defense is backing away from threats.
	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null and band != MoraleBand.BROKEN:
		_kite_from(threat, KITE_SPEED)
	else:
		velocity = Vector2.ZERO


func _tick_heal() -> void:
	# Heal EVERY wounded same-team living human in radius — order-independent
	# by construction (Rule #4 safe). Mirrors Medic._tick_heal exactly.
	var team_group: String = "player_units" if is_in_group("player_units") else "ai_units"
	var healed_any: bool = false
	for u in get_tree().get_nodes_in_group(team_group):
		if u == self or not is_instance_valid(u):
			continue
		if not ("current_hp" in u) or u.current_hp <= 0:
			continue
		if "faction" in u and u.faction == GameState.Faction.ZOMBIE:
			continue
		if global_position.distance_to(u.global_position) > HEAL_RADIUS_PX:
			continue
		var max_eff: int = u.get_effective_max_hp() if u.has_method("get_effective_max_hp") else u.max_hp
		if u.current_hp >= max_eff:
			continue
		u.current_hp = min(max_eff, u.current_hp + HEAL_PER_TICK)
		if u.has_method("queue_redraw"):
			u.queue_redraw()  # HP bar refresh — render-only side effect
		healed_any = true
	if healed_any:
		queue_redraw()
		_attack_anim_timer = HEAL_ANIM_HOLD


func _draw() -> void:
	super._draw()
	# Support marker (§10.5 focus-fire legibility): a pale green flask dot
	# on the chest — same slot the Medic's red cross occupies, different
	# silhouette so the two factions' support units never read alike.
	if use_sprite:
		return
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var s: float = float(size_px) / 22.0
	var flask_color := Color(0.45, 0.72, 0.38)
	draw_circle(Vector2(0, -10.0 * s), 2.4 * s, flask_color)
