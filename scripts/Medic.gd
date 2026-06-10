extends "res://scripts/CombatUnit.gd"

# Military Medic (DESIGN_MASTER §7.1, v1). The support unit that keeps the
# line alive: slow ambient healing in a radius (the mobile version of the
# medic-tent "clean zone") plus a morale-recovery aura (CombatUnit reads the
# "medics" group in _tick_morale — a shaken squad calms twice as fast with a
# Medic standing in it). Unarmed: the Medic's only verbs are heal, follow,
# and run. Doctrines (Stim / Graves) are deferred [PROPOSED]; bleeding/
# stabilize waits on the blood-scent channel landing.
#
# §7.1 "Medic threshold: the corpse ledger and the fear ledger" — v1 covers
# the fear ledger (morale aura). The corpse ledger (your healed men don't
# die, so they don't rise) is emergent from the healing itself.
#
# Readability (§10.5): support units need a distinct readable element for
# focus-fire legibility. Procedural era: pale smock body color + a red
# cross painted over the chest in _draw. Sprite art carries this later.

# Heal numbers: deliberately SLOW per §2 ("healing HP is slow and
# expensive") — 4 HP/s spread over everyone in radius would trivialize
# attrition; 2 HP/s per wounded ally inside 3 tiles is triage, not
# invulnerability. Placeholders for the lab.
const HEAL_RADIUS_PX := 96.0          # 3 tiles — stand IN the squad
const HEAL_PER_TICK := 2              # int HP per beneficiary per tick
const HEAL_TICK_INTERVAL := 1.0       # sim seconds
const KITE_RANGE := 120.0             # backs away a little earlier than Hunter (unarmed)
const KITE_SPEED := 34.0
const THREAT_CHECK_INTERVAL := 0.2    # 5 Hz threat poll, substrate cadence

var _heal_timer: float = 0.0
var _threat_check_timer: float = 0.0
var _threat_cached = null


# Morale + personality per §5.1 — the Medic is a Military combat-line unit
# and can himself shake/break (a broken Medic fleeing the line is exactly
# the §5.1 fear-ledger texture).
func _morale_enabled() -> bool:
	return true


func _ready() -> void:
	super._ready()
	# CombatUnit._tick_morale scans this group for the recovery aura.
	add_to_group("medics")


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	var band: int = _tick_morale(delta)
	# Healing runs in every command state — triage doesn't stop because the
	# squad is marching. Fixed-interval accumulator on the physics tick.
	_heal_timer += delta
	if _heal_timer >= HEAL_TICK_INTERVAL:
		_heal_timer = 0.0
		_tick_heal()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	if current_command == Command.FLEE:
		# BROKEN morale routed nav to the flee target in CombatUnit; walk it.
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
	# Heal EVERY wounded same-team living human in radius (no target
	# selection — order-independent by construction, Rule #4 safe). Zombies
	# excluded by faction; buildings aren't in the units group.
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
		queue_redraw()  # pulse our own cross accent (cheap tell that triage is live)


func _draw() -> void:
	super._draw()
	# Red cross on the chest — the §10.5 focus-fire-legible support marker.
	# Same iso transform Unit._draw uses so the accent sits on the body.
	if use_sprite:
		return
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)
	var s: float = float(size_px) / 22.0
	var cross_y: float = -10.0 * s
	var arm: float = 2.6 * s
	var thick: float = 1.4 * s
	var cross_color := Color(0.78, 0.16, 0.16)
	draw_rect(Rect2(-arm, cross_y - thick * 0.5, arm * 2.0, thick), cross_color)
	draw_rect(Rect2(-thick * 0.5, cross_y - arm, thick, arm * 2.0), cross_color)
