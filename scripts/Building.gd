class_name Building
extends StaticBody2D

# Building base class. In Phase 4 of the three-quarters perspective conversion
# the body renders as a proper iso 3D structure - footprint base on the ground,
# two visible walls (south + east, the camera-facing pair), and a roof.
#
# The node itself stays at world coordinates (so gameplay - range checks, nav
# obstructions, child spawn offsets - operates on the same numbers as before).
# Rendering applies draw_set_transform with an iso offset so the visible building
# lands at IsoView.world_to_screen(position), which is where the iso ground tile
# under that world coord renders. Building and ground stay visually aligned.
# Click detection is still in world space (Phase 6 will project it to iso).

signal destroyed(building)

const PALETTE_STRUCTURE := Color("4a4339")
const PALETTE_MILITARY := Color("5a6644")
const PALETTE_SURVIVOR := Color("7a5c3c")
const PALETTE_TRIBAL := Color("8a6a3a")
const PALETTE_ICON_NEUTRAL := Color("8a857a")

@export var max_hp: int = 1000
@export var body_color: Color = Color.WHITE
@export var size_pixels: Vector2 = Vector2(64, 64)
# Wall height in screen pixels. Bigger / more imposing buildings (HQs) override
# to push this higher in their scene or _ready.
@export var wall_height: float = 32.0

var current_hp: int
var selected: bool = false
# A2: set by AIController on the buildings it spawns so damage events reach
# the controller's SURVIVE posture. Null for player buildings (HUD/GameState
# own those flows). Untyped to avoid a cyclic class reference.
var owner_controller = null


# ---- Building skin ("skin the maps" pass 2, 2026-06-11). RENDER-ONLY.
# Subclasses name their PNG via _get_skin_path(); when it loads, _draw
# renders the art bottom-anchored on the footprint diamond instead of the
# procedural prism. Missing/failed art falls back to the prism (the same
# defensive boundary GroundTiles uses). State overlays (selection ring,
# HP bar, infested tint) draw on top in both modes — they're game state,
# not skin.
var _skin: Texture2D = null
# Occlusion fade (Matt's call, 2026-06-11): tall art must never hide
# units. When a unit stands BEHIND the building (deeper in iso depth and
# inside the art's screen rect), the skin fades to FADE_ALPHA. Checked at
# 5 Hz in _process — render-only, no sim reads back.
const FADE_ALPHA := 0.45
# Height cap: art taller than this multiple of its footprint width gets
# clamped (mid-rise world; also bounds the occlusion shadow).
const SKIN_MAX_HEIGHT_RATIO := 1.4
# Art overflows its lot (2026-06-11 screenshot pass): width-scaling art
# exactly to the footprint diamond made buildings read as doll houses.
# Real iso games draw building art LARGER than its collision footprint;
# the occlusion fade keeps units readable behind the overflow.
const SKIN_OVERSCAN := 1.5
var _skin_faded: bool = false
# Per-lot variety (MapCraft A gate finding): the same PNG repeated across
# a district is the loudest "asset flip" tell. Mirror + small value
# jitter by position hash — deterministic, render-only, doubles apparent
# variety for free.
var _skin_flip: bool = false
var _skin_value: float = 1.0


# ---- Faction ground identity (MapCraft C, Matt's directive: every
# faction's identity present in their spawn). Faction buildings spawn
# render-only dressing — a ground halo + identity props (totems,
# sandbags, pallets) — as siblings, freed when the building dies.
# Applies to RUNTIME construction too, so a forward base claims its
# ground the moment it stands. Deterministic offsets/picks by position
# hash; zero sim surface.
const DRESSING_BY_FACTION := {
	"military": {
		"halo": "res://assets/props/decal_military_ground.png",
		"props": ["res://assets/props/sandbag_wall.png", "res://assets/props/oil_barrel.png", "res://assets/props/traffic_cone.png"],
	},
	"tribal": {
		"halo": "res://assets/props/decal_tribal_ground.png",
		"props": ["res://assets/props/totem_tribal.png"],
	},
	"survivor": {
		"halo": "res://assets/props/decal_survivor_ground.png",
		"props": ["res://assets/props/wood_pallet.png", "res://assets/props/oil_barrel.png", "res://assets/props/shopping_cart.png"],
	},
}
# Ring offsets (x half-extent multiples) — fixed table, no transcendentals.
const DRESSING_OFFSETS := [
	Vector2(1.45, 0.3), Vector2(-1.4, 0.7), Vector2(0.5, -1.5),
	Vector2(-0.6, -1.4), Vector2(1.2, 1.15), Vector2(-1.35, -0.5),
]
var _dressing_nodes: Array = []


func _get_faction_dressing() -> String:
	return ""  # subclasses return "military"/"tribal"/"survivor"


func _spawn_dressing() -> void:
	var cfg: Dictionary = DRESSING_BY_FACTION.get(_get_faction_dressing(), {})
	if cfg.is_empty() or get_parent() == null:
		return
	var h: int = ((int(position.x) * 2654435761) ^ (int(position.y) * 40503)) & 0x7FFFFFFF
	# Halo under the building.
	if ResourceLoader.exists(cfg["halo"]):
		var halo := Node2D.new()
		halo.set_script(preload("res://scripts/GroundHalo.gd"))
		halo.position = position
		halo.texture = load(cfg["halo"])
		halo.scale_factor = maxf(size_pixels.x, size_pixels.y) / 64.0 * 2.2
		get_parent().add_child(halo)
		_dressing_nodes.append(halo)
	# Identity props ringed around the footprint.
	var avail: Array = []
	for p in cfg["props"]:
		if ResourceLoader.exists(p):
			avail.append(load(p))
	if not avail.is_empty():
		var count: int = 2 + ((h >> 6) % 2)  # 2-3 props
		for i in range(count):
			var off: Vector2 = DRESSING_OFFSETS[((h >> 8) + i * 2) % DRESSING_OFFSETS.size()]
			var prop := Node2D.new()
			prop.set_script(preload("res://scripts/Prop.gd"))
			prop.position = position + off * (size_pixels * 0.5 + Vector2(20, 20))
			prop.texture = avail[((h >> 10) + i) % avail.size()]
			get_parent().add_child(prop)
			_dressing_nodes.append(prop)
	tree_exiting.connect(_free_dressing)


func _free_dressing() -> void:
	for n in _dressing_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_dressing_nodes.clear()


func _get_skin_path() -> String:
	return ""  # subclasses override; "" = procedural prism


func _get_skin_modulate() -> Color:
	return Color.WHITE  # subclasses tint (infested, scenery darkening)


func _ready() -> void:
	current_hp = max_hp
	add_to_group("buildings")
	# Iso depth sort - back corner depth so units in front of the building
	# render after it. Set once; buildings don't move.
	var back_corner: Vector2 = global_position - size_pixels * 0.5
	z_index = IsoView.z_for(back_corner)
	var skin_path := _get_skin_path()
	if skin_path != "" and ResourceLoader.exists(skin_path):
		_skin = load(skin_path)
	if _skin != null:
		add_to_group("skinned_buildings")  # BuildingFadeSweep polls these
	if _get_faction_dressing() != "":
		# Deferred: parent must finish adding us before we add siblings.
		call_deferred("_spawn_dressing")
		# Positions sit on a 32px lattice, so a multiplicative hash keeps
		# its LOW bits zero — pick decision bits from the high half.
		var h: int = ((int(position.x) * 2654435761) ^ (int(position.y) * 40503)) & 0x7FFFFFFF
		_skin_flip = ((h >> 9) & 1) == 1
		# Never mirror signage — reversed "DINER" text is a worse tell than
		# repetition (gate finding, 2026-06-11).
		for kw in ["diner", "storefront", "commercial", "police", "grocer"]:
			if kw in skin_path:
				_skin_flip = false
				break
		_skin_value = 0.94 + float((h >> 13) % 11) * 0.01  # 0.94..1.04


func update_fade(units: Array) -> void:
	# Called by BuildingFadeSweep (amortized — a slice of buildings per
	# frame; the original per-building 5 Hz self-poll fired every building
	# on the SAME frame and hitched the game 5x/sec). RENDER-ONLY.
	var was: bool = _skin_faded
	_skin_faded = _any_unit_behind(units)
	if _skin_faded != was:
		queue_redraw()


func _any_unit_behind(units: Array) -> bool:
	var hw: float = size_pixels.x * 0.5
	var hh: float = size_pixels.y * 0.5
	var c: Vector2 = IsoView.world_to_screen(position)
	var diamond_w: float = (IsoView.world_to_screen(Vector2(hw, -hh)) - IsoView.world_to_screen(Vector2(-hw, hh))).x * SKIN_OVERSCAN
	var tex_size: Vector2 = _skin.get_size()
	var draw_h: float = minf(diamond_w * tex_size.y / tex_size.x, diamond_w * SKIN_MAX_HEIGHT_RATIO)
	var base_y: float = c.y + IsoView.world_to_screen(Vector2(hw, hh)).y
	var top_y: float = base_y - draw_h
	var depth: float = position.x + position.y
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.global_position.x + u.global_position.y >= depth:
			continue  # in front of or beside us in iso depth
		var s: Vector2 = IsoView.world_to_screen(u.global_position)
		if absf(s.x - c.x) < diamond_w * 0.5 and s.y > top_y and s.y < base_y:
			return true
	return false


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func take_damage(amount: int, attacker = null) -> void:
	# Mirrors Unit.take_damage: credit attacker for damage and (on destruction)
	# the kill, so XP/veterancy works for unit-vs-building too. Pre-C1 this
	# took only `amount` and Brawler's `self`-passing call crashed the game.
	if current_hp <= 0:
		return
	var actual: int = min(amount, current_hp)
	if attacker != null and is_instance_valid(attacker) and "damage_dealt" in attacker:
		attacker.damage_dealt += float(actual)
	current_hp = max(0, current_hp - amount)
	queue_redraw()
	# A2 (AI_OVERHAUL_PLAN): AI-owned buildings report damage to their
	# controller so the SURVIVE posture can preempt. The attacker's position
	# (when known) becomes the defend rally point.
	if owner_controller != null and is_instance_valid(owner_controller):
		if owner_controller.has_method("notify_building_damaged"):
			owner_controller.notify_building_damaged(self, attacker)
	if current_hp == 0:
		if attacker != null and is_instance_valid(attacker) and "kills_count" in attacker:
			attacker.kills_count += 1
		_die()


func get_action_count() -> int:
	return 0


func get_action_text(_idx: int) -> String:
	return ""


func get_action_available(_idx: int) -> bool:
	return false


func do_action(_idx: int) -> void:
	pass


func get_status_text() -> String:
	return ""


func _die() -> void:
	destroyed.emit(self)
	queue_free()


func _draw() -> void:
	# Apply the iso shift so the visible building lands at IsoView projection
	# of our world-coord position. Everything drawn below this call is in iso
	# screen-space relative to the iso-projected center.
	var iso_offset: Vector2 = IsoView.world_to_screen(position) - position
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	var hw: float = size_pixels.x * 0.5
	var hh: float = size_pixels.y * 0.5

	# Project the four footprint corners to iso (offsets from node origin).
	# IsoView's projection is linear, so projecting a relative offset gives
	# the relative iso offset.
	var nw: Vector2 = IsoView.world_to_screen(Vector2(-hw, -hh))
	var ne: Vector2 = IsoView.world_to_screen(Vector2(hw, -hh))
	var se: Vector2 = IsoView.world_to_screen(Vector2(hw, hh))
	var sw: Vector2 = IsoView.world_to_screen(Vector2(-hw, hh))

	var nw_top: Vector2 = nw + Vector2(0.0, -wall_height)
	var ne_top: Vector2 = ne + Vector2(0.0, -wall_height)
	var se_top: Vector2 = se + Vector2(0.0, -wall_height)
	var sw_top: Vector2 = sw + Vector2(0.0, -wall_height)

	# ---- Skinned path: art instead of the prism. Bottom-anchored on the
	# footprint diamond, width-scaled to the projected diamond, aspect
	# preserved. The darkened footprint stays as the grounding shadow.
	if _skin != null:
		var diamond_w: float = ne.x - sw.x
		var tex_size: Vector2 = _skin.get_size()
		var draw_w: float = diamond_w * SKIN_OVERSCAN
		var draw_h: float = minf(draw_w * tex_size.y / tex_size.x, draw_w * SKIN_MAX_HEIGHT_RATIO)
		# Base sits at the south corner's y, pulled up slightly so the art's
		# foundation overlaps the shadow instead of floating below it.
		var base_y: float = se.y + 2.0
		# Drop shadow (MapCraft A, 2026-06-11): one light source for the
		# whole world — every standing object casts the same soft SE shadow.
		# The references ground every sprite this way; it's the single
		# biggest "sits IN the world" cue. Footprint diamond shifted SE and
		# widened, drawn before the art.
		var sh_off := Vector2(diamond_w * 0.10, 3.0)
		draw_colored_polygon(PackedVector2Array([
			nw + sh_off, ne + sh_off + Vector2(diamond_w * 0.08, 0),
			se + sh_off + Vector2(diamond_w * 0.08, 2.0), sw + sh_off,
		]), Color(0.04, 0.04, 0.05, 0.40))
		var mod: Color = _get_skin_modulate()
		mod = Color(mod.r * _skin_value, mod.g * _skin_value, mod.b * _skin_value, mod.a)
		if _skin_faded:
			mod.a *= FADE_ALPHA
		if _skin_flip:
			draw_set_transform(iso_offset, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(_skin, Rect2(-draw_w * 0.5, base_y - draw_h, draw_w, draw_h), false, mod)
		if _skin_flip:
			draw_set_transform(iso_offset, 0.0, Vector2.ONE)
		if selected:
			draw_polyline(PackedVector2Array([nw, ne, se, sw, nw]), Color(1, 1, 0.4), 2.0, true)
		if current_hp < max_hp:
			var sbar_w: float = max(size_pixels.x * 0.7, 32.0)
			var sbar_y: float = base_y - draw_h - 10.0
			draw_rect(Rect2(-sbar_w * 0.5, sbar_y, sbar_w, 3.0), Color(0.12, 0.05, 0.05))
			var sfill: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
			draw_rect(Rect2(-sbar_w * 0.5, sbar_y, sbar_w * sfill, 3.0), Color(0.35, 0.65, 0.3))
		return

	# Ground footprint - reads as the building's shadow/base ring.
	draw_colored_polygon(PackedVector2Array([nw, ne, se, sw]), body_color.darkened(0.55))

	# South wall (front, faces camera).
	draw_colored_polygon(PackedVector2Array([sw, se, se_top, sw_top]), body_color)

	# East wall (right side) - slightly darker so the two visible walls separate
	# instead of melting together.
	draw_colored_polygon(PackedVector2Array([se, ne, ne_top, se_top]), body_color.darkened(0.20))

	# Roof - slightly lighter, top-down read of the building's top surface.
	draw_colored_polygon(PackedVector2Array([nw_top, ne_top, se_top, sw_top]), body_color.lightened(0.22))

	# Edge outlines to define the form.
	var edge: Color = body_color.darkened(0.45)
	draw_line(sw, se, edge, 1.0)
	draw_line(se, ne, edge, 1.0)
	draw_line(sw, sw_top, edge, 1.0)
	draw_line(se, se_top, edge, 1.0)
	draw_line(ne, ne_top, edge, 1.0)
	draw_line(nw_top, ne_top, edge, 1.0)
	draw_line(ne_top, se_top, edge, 1.0)
	draw_line(se_top, sw_top, edge, 1.0)
	draw_line(sw_top, nw_top, edge, 1.0)

	# Door on the south wall.
	_draw_south_door(sw, se, sw_top, se_top)

	# Subclass icon - shift the canvas to the roof center so existing
	# _draw_building_icon implementations (which draw at local Vector2.ZERO)
	# appear on the roof of the iso building instead of at the ground center.
	var roof_center: Vector2 = (nw_top + se_top) * 0.5
	draw_set_transform(iso_offset + roof_center, 0.0, Vector2.ONE)
	_draw_building_icon()
	draw_set_transform(iso_offset, 0.0, Vector2.ONE)

	# Selection ring around the roof.
	if selected:
		draw_polyline(PackedVector2Array([nw_top, ne_top, se_top, sw_top, nw_top]), Color(1, 1, 0.4), 2.0, true)

	# HP bar floats above the roof.
	if current_hp < max_hp:
		var bar_w: float = max(size_pixels.x * 0.7, 32.0)
		var bar_y: float = nw_top.y - 10.0
		var bar_x: float = -bar_w * 0.5
		draw_rect(Rect2(bar_x, bar_y, bar_w, 3.0), Color(0.12, 0.05, 0.05))
		var fill_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		draw_rect(Rect2(bar_x, bar_y, bar_w * fill_ratio, 3.0), Color(0.35, 0.65, 0.3))


func _draw_south_door(sw: Vector2, se: Vector2, sw_top: Vector2, se_top: Vector2) -> void:
	var bottom_mid: Vector2 = (sw + se) * 0.5
	var top_mid: Vector2 = (sw_top + se_top) * 0.5
	var to_top: Vector2 = top_mid - bottom_mid
	var wall_dir: Vector2 = (se - sw)
	var half_door: Vector2 = wall_dir * 0.10
	var door_top: Vector2 = to_top * 0.55
	var bl: Vector2 = bottom_mid - half_door
	var br: Vector2 = bottom_mid + half_door
	var tl: Vector2 = bl + door_top
	var tr: Vector2 = br + door_top
	draw_colored_polygon(PackedVector2Array([bl, br, tr, tl]), body_color.darkened(0.55))


# Legacy hook - subclasses override to draw a type marker. The canvas is
# transformed so subclass draws at their local Vector2.ZERO appear at the
# building's roof center. Kept the old name so existing subclass overrides
# (CommandPost, TribalCamp, SettlementHub, Lootable variants) just work.
func _draw_building_icon() -> void:
	pass
