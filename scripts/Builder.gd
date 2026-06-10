extends "res://scripts/CombatUnit.gd"

# Survivor Builder (DESIGN_MASTER §7.3, v1) — the faction's construction
# worker: places Farms and Radio Stations through the shared SC-style
# placement flow (BuildCatalog → SelectionManager ghost → ConstructionSite
# channel). Unarmed; renovation is the weapon.
#
# CONNECTED 2026-06-10 (Matt's go): the SettlementHub "builder" row
# produces this scene (replacing the borrowed Engineer); construct routing
# was already generic. Palisades + garrison conversion (the §7.3 endgame
# of this unit) are deferred — garrisons are a system, not a unit feature.

const BuildCatalogRef := preload("res://scripts/BuildCatalog.gd")

enum Sub { NONE, CONSTRUCT_APPROACH, CONSTRUCT_CHANNEL }

const CONSTRUCT_RANGE := 80.0
const KITE_RANGE := 110.0
const KITE_SPEED := 32.0
const THREAT_CHECK_INTERVAL := 0.2

const SPRITE_ROOT := "res://assets/sprites/units/survivor/builder/"
const WORK_ANIM_HOLD := 0.6

var _sub: int = Sub.NONE
var _construct_site = null
var _threat_check_timer: float = 0.0
var _threat_cached = null


func _get_sprite_root() -> String:
	return SPRITE_ROOT


func _morale_enabled() -> bool:
	return true


func _ready() -> void:
	super._ready()
	_init_sprite()


# ---- Construction (mirrors Looter.construct_at — the shared worker verb) ----

func construct_at(site) -> void:
	if site == null or not is_instance_valid(site):
		return
	_construct_site = site
	_sub = Sub.CONSTRUCT_APPROACH
	_nav.target_position = site.position


func move_to(world_pos: Vector2) -> void:
	super.move_to(world_pos)
	_sub = Sub.NONE
	_construct_site = null


func _tick_construct_approach() -> void:
	if _construct_site == null or not is_instance_valid(_construct_site):
		_construct_site = null
		_sub = Sub.NONE
		return
	var reach: float = CONSTRUCT_RANGE + maxf(_construct_site.size_pixels.x, _construct_site.size_pixels.y) * 0.5
	if global_position.distance_to(_construct_site.position) <= reach:
		_sub = Sub.CONSTRUCT_CHANNEL
		velocity = Vector2.ZERO
	else:
		_follow_navigation()


func _tick_construct_channel(delta: float) -> void:
	velocity = Vector2.ZERO
	_attack_anim_timer = WORK_ANIM_HOLD  # hammer-swing anim while channeling
	if _construct_site == null or not is_instance_valid(_construct_site):
		_construct_site = null
		_sub = Sub.NONE
		return
	if _construct_site.advance_construction(delta):
		_construct_site = null
		_sub = Sub.NONE


# ---- HUD build actions (worker-as-builder, same shape as Looter/Walker) ----

func get_action_count() -> int:
	return BuildCatalogRef.catalog_for(faction).size()


func get_action_text(idx: int) -> String:
	var keys: Array = BuildCatalogRef.catalog_for(faction).keys()
	if idx < 0 or idx >= keys.size():
		return ""
	var e: Dictionary = BuildCatalogRef.catalog_for(faction)[keys[idx]]
	return "Build %s (%d Salvage)" % [e["name"], int(e["cost"])]


func get_action_available(idx: int) -> bool:
	var keys: Array = BuildCatalogRef.catalog_for(faction).keys()
	if idx < 0 or idx >= keys.size():
		return false
	return GameState.can_spend(int(BuildCatalogRef.catalog_for(faction)[keys[idx]]["cost"]))


func do_action(idx: int) -> void:
	var keys: Array = BuildCatalogRef.catalog_for(faction).keys()
	if idx < 0 or idx >= keys.size():
		return
	var key: String = keys[idx]
	var sel = get_tree().get_first_node_in_group("selection_manager")
	if sel != null and sel.has_method("start_building_placement"):
		sel.start_building_placement(self, key, BuildCatalogRef.catalog_for(faction)[key])


func get_status_text() -> String:
	match _sub:
		Sub.CONSTRUCT_APPROACH: return "Moving to site"
		Sub.CONSTRUCT_CHANNEL: return "Building"
		_: return "Idle"


func _physics_process(delta: float) -> void:
	_sim_upkeep(delta)  # D4 subclass invariant — see Unit._sim_upkeep
	_attack_anim_timer = max(0.0, _attack_anim_timer - delta)
	if use_sprite:
		_update_sprite_animation()
	if current_command == Command.CREMATE:
		velocity = Vector2.ZERO
		return
	var band: int = _tick_morale(delta)
	if current_command == Command.FLEE:
		_follow_navigation()
		return
	if current_command == Command.MOVE:
		var still_moving := _follow_navigation()
		if not still_moving:
			current_command = Command.IDLE
		return
	# IDLE: construction subsumes idling; otherwise back away from threats.
	match _sub:
		Sub.CONSTRUCT_APPROACH:
			_tick_construct_approach()
			return
		Sub.CONSTRUCT_CHANNEL:
			_tick_construct_channel(delta)
			return
	_threat_check_timer -= delta
	if _threat_check_timer <= 0.0:
		_threat_check_timer = THREAT_CHECK_INTERVAL
		_threat_cached = _find_nearest_threat_in_range(KITE_RANGE)
	var threat = _threat_cached if (_threat_cached != null and is_instance_valid(_threat_cached)) else null
	if threat != null and band != MoraleBand.BROKEN:
		_kite_from(threat, KITE_SPEED)
	else:
		velocity = Vector2.ZERO
