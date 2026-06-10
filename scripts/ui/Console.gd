extends PanelContainer

# The bottom console (SC1/SC2 HUD study, 2026-06-10). Three sections on
# the SC layout: minimap left, selection panel center, command card
# right. Built entirely in code (theme included) so the whole look is
# diffable and tunable without scene surgery.
#
# RENDER-ONLY: reads selection + actor state, issues actions through the
# same do_action path the old panel used. Hotkeys follow the SC2 grid
# (Q W E / A S D / Z C V — X stays the stance hotkey, G stays squads).

const CARD_HOTKEYS := [KEY_Q, KEY_W, KEY_E, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_C, KEY_V]
const CARD_LABELS := ["Q", "W", "E", "A", "S", "D", "Z", "C", "V"]
const CONSOLE_HEIGHT := 184.0
const PORTRAIT_PX := 96.0

# Palette: gunmetal console, bone text, faction accent.
const COL_PANEL := Color(0.085, 0.09, 0.095, 0.97)
const COL_PANEL_IN := Color(0.115, 0.12, 0.125, 1.0)
const COL_BORDER := Color(0.30, 0.29, 0.25)
const COL_TEXT := Color(0.85, 0.83, 0.76)
const COL_TEXT_DIM := Color(0.55, 0.53, 0.48)
const COL_ACCENT := Color(0.55, 0.62, 0.42)  # olive — Military default
const COL_HP_OK := Color(0.42, 0.68, 0.36)
const COL_HP_BAD := Color(0.78, 0.32, 0.25)

var _minimap: Control = null
var _portrait: TextureRect = null
var _portrait_fallback: ColorRect = null
var _sel_name: Label = null
var _sel_hp: ProgressBar = null
var _sel_status: Label = null
var _multi_grid: GridContainer = null
var _card_buttons: Array = []
var _actor = null
var _selected: Array = []


func _ready() -> void:
	_build_theme_and_layout()
	var sel_mgr := get_tree().get_first_node_in_group("selection_manager")
	if sel_mgr != null:
		sel_mgr.selection_changed.connect(_on_selection_changed)


# ------------------------------------------------------------- layout

func _panel_style(inner: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_IN if inner else COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(2 if not inner else 1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8 if not inner else 6)
	# Top accent line on the outer console — the faction color strip.
	if not inner:
		sb.border_width_top = 3
		sb.border_color = COL_BORDER
	return sb


func _button_style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"hover":
			sb.bg_color = Color(0.18, 0.19, 0.18)
			sb.border_color = COL_ACCENT
		"pressed":
			sb.bg_color = Color(0.07, 0.075, 0.07)
			sb.border_color = COL_ACCENT
		"disabled":
			sb.bg_color = Color(0.10, 0.10, 0.10)
			sb.border_color = Color(0.20, 0.20, 0.18)
		_:
			sb.bg_color = Color(0.14, 0.145, 0.14)
			sb.border_color = Color(0.34, 0.33, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(4)
	return sb


func _build_theme_and_layout() -> void:
	# Console anchors: full-width bottom bar.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -CONSOLE_HEIGHT
	offset_left = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	add_theme_stylebox_override("panel", _panel_style())
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks on console never reach the world

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- Minimap (left) ---
	var mm_frame := PanelContainer.new()
	mm_frame.add_theme_stylebox_override("panel", _panel_style(true))
	row.add_child(mm_frame)
	_minimap = preload("res://scripts/ui/Minimap.gd").new()
	_minimap.custom_minimum_size = Vector2(156, 156)
	mm_frame.add_child(_minimap)

	# --- Selection panel (center, expands) ---
	var sel_frame := PanelContainer.new()
	sel_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_frame.add_theme_stylebox_override("panel", _panel_style(true))
	row.add_child(sel_frame)
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 10)
	sel_frame.add_child(sel_row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(PORTRAIT_PX + 8, PORTRAIT_PX + 8)
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(true))
	sel_row.add_child(portrait_frame)
	_portrait_fallback = ColorRect.new()
	_portrait_fallback.color = Color(0.2, 0.2, 0.2)
	portrait_frame.add_child(_portrait_fallback)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art stays crisp
	portrait_frame.add_child(_portrait)

	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 4)
	sel_row.add_child(info_col)
	_sel_name = Label.new()
	_sel_name.add_theme_color_override("font_color", COL_TEXT)
	_sel_name.add_theme_font_size_override("font_size", 16)
	info_col.add_child(_sel_name)
	_sel_hp = ProgressBar.new()
	_sel_hp.custom_minimum_size = Vector2(0, 14)
	_sel_hp.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.07, 0.06, 0.06)
	hp_bg.set_border_width_all(1)
	hp_bg.border_color = COL_BORDER
	_sel_hp.add_theme_stylebox_override("background", hp_bg)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = COL_HP_OK
	_sel_hp.add_theme_stylebox_override("fill", hp_fill)
	info_col.add_child(_sel_hp)
	_sel_status = Label.new()
	_sel_status.add_theme_color_override("font_color", COL_TEXT_DIM)
	_sel_status.add_theme_font_size_override("font_size", 12)
	_sel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(_sel_status)
	_multi_grid = GridContainer.new()
	_multi_grid.columns = 12
	_multi_grid.add_theme_constant_override("h_separation", 3)
	_multi_grid.add_theme_constant_override("v_separation", 3)
	info_col.add_child(_multi_grid)

	# --- Command card (right): 3x3 SC grid ---
	var card_frame := PanelContainer.new()
	card_frame.add_theme_stylebox_override("panel", _panel_style(true))
	row.add_child(card_frame)
	var card := GridContainer.new()
	card.columns = 3
	card.add_theme_constant_override("h_separation", 4)
	card.add_theme_constant_override("v_separation", 4)
	card_frame.add_child(card)
	for i in range(9):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(86, 46)
		btn.clip_text = true
		btn.add_theme_color_override("font_color", COL_TEXT)
		btn.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_stylebox_override("normal", _button_style("normal"))
		btn.add_theme_stylebox_override("hover", _button_style("hover"))
		btn.add_theme_stylebox_override("pressed", _button_style("pressed"))
		btn.add_theme_stylebox_override("disabled", _button_style("disabled"))
		btn.visible = false
		btn.pressed.connect(_on_card_pressed.bind(i))
		card.add_child(btn)
		_card_buttons.append(btn)


# ------------------------------------------------------------- selection

func _on_selection_changed(units: Array, building) -> void:
	_selected = []
	for u in units:
		if is_instance_valid(u):
			_selected.append(u)
	if building != null and is_instance_valid(building) and GameState.is_owned_by_player(building):
		_actor = building
	elif _selected.size() >= 1:
		_actor = _selected[0]
	else:
		_actor = null
	_refresh_selection_panel()


func _portrait_texture_for(node) -> Texture2D:
	# Real art as portraits: the unit's south idle frame. Buildings and
	# sprite-less units fall back to a faction color block.
	var sprite: AnimatedSprite2D = node.get_node_or_null("AnimatedSprite2D")
	if sprite != null and sprite.sprite_frames != null:
		for anim in ["idle_south", "idle"]:
			if sprite.sprite_frames.has_animation(anim) and sprite.sprite_frames.get_frame_count(anim) > 0:
				return sprite.sprite_frames.get_frame_texture(anim, 0)
	return null


func _refresh_selection_panel() -> void:
	for c in _multi_grid.get_children():
		c.queue_free()
	if _actor == null or not is_instance_valid(_actor):
		_portrait.texture = null
		_portrait_fallback.color = Color(0.13, 0.13, 0.13)
		_sel_name.text = ""
		_sel_hp.visible = false
		_sel_status.text = ""
		return
	var tex := _portrait_texture_for(_actor)
	_portrait.texture = tex
	_portrait_fallback.color = _actor.body_color.darkened(0.3) if "body_color" in _actor else Color(0.13, 0.13, 0.13)
	_sel_name.text = String(_actor.name)
	_sel_hp.visible = true
	# Multi-select: mini-portrait strip (click selects nothing yet — display).
	if _selected.size() > 1:
		for u in _selected:
			if not is_instance_valid(u):
				continue
			var mini := TextureRect.new()
			mini.custom_minimum_size = Vector2(26, 26)
			mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mini.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var t := _portrait_texture_for(u)
			if t != null:
				mini.texture = t
			_multi_grid.add_child(mini)


# ------------------------------------------------------------- card

func _on_card_pressed(i: int) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _actor is Building and not GameState.is_owned_by_player(_actor):
		return
	if _actor.has_method("do_action"):
		_actor.do_action(i)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := CARD_HOTKEYS.find(event.keycode)
		if idx >= 0 and idx < _card_buttons.size() and _card_buttons[idx].visible and not _card_buttons[idx].disabled:
			_on_card_pressed(idx)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Card + HP refresh (UI cadence; cheap).
	var count: int = 0
	if _actor != null and is_instance_valid(_actor) and _actor.has_method("get_action_count"):
		count = _actor.get_action_count()
	for i in range(_card_buttons.size()):
		var btn: Button = _card_buttons[i]
		if _actor != null and is_instance_valid(_actor) and i < count:
			btn.visible = true
			btn.text = "[%s] %s" % [CARD_LABELS[i], _actor.get_action_text(i)]
			btn.disabled = not _actor.get_action_available(i)
		else:
			btn.visible = false
	if _actor != null and is_instance_valid(_actor):
		if "current_hp" in _actor:
			var max_hp: int = _actor.get_effective_max_hp() if _actor.has_method("get_effective_max_hp") else (_actor.max_hp if "max_hp" in _actor else 1)
			_sel_hp.max_value = max_hp
			_sel_hp.value = _actor.current_hp
			var fill: StyleBoxFlat = _sel_hp.get_theme_stylebox("fill")
			fill.bg_color = COL_HP_OK if float(_actor.current_hp) / float(max_hp) > 0.35 else COL_HP_BAD
			_sel_name.text = "%s   %d/%d" % [String(_actor.name), _actor.current_hp, max_hp]
		if _actor.has_method("get_status_text"):
			_sel_status.text = _actor.get_status_text()
		elif _actor.has_method("get_status_text_for_hud"):
			_sel_status.text = _actor.get_status_text_for_hud()
		else:
			_sel_status.text = ""
	elif _actor != null and not is_instance_valid(_actor):
		_actor = null
		_refresh_selection_panel()
