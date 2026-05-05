extends PanelContainer
##
## Single ability slot in the rail (one of Q/E/F/R). Mirrors `.ab-slot`
## from `design/src/components.css`.
##
## Public API:
##   - configure(key_label, hero_id)
##   - set_glyph_text(text)        → primary letter / mini-icon when ready
##   - set_cooldown(remaining, max) → enters cooldown mode while remaining > 0
##   - set_hero(hero_id)            → re-skin border with hero core color

const TotemHelper := preload("res://scripts/ui/components/totem_image.gd")

const SLOT_SIZE := 56
const KEY_CHIP_SIZE := 18

var _key_label: String = "Q"
var _hero_id: String = "Buffalo"
var _glyph: String = ""
var _cooldown: float = 0.0
var _cooldown_max: float = 0.0
var _show_totem_when_ready: bool = false
# Locked state — slot is reserved for a future ability (M3+) so it should
# read as "intentionally empty", not "broken". When locked we draw an em
# dash glyph at low contrast and dial the panel's overall opacity down.
var _locked: bool = false

# Children
var _key_panel: PanelContainer
var _key_text: Label
var _glyph_label: Label
var _totem: Control
var _cd_progress: Panel  # bottom progress bar — hand-drawn rect

func _ready() -> void:
	_build()
	_apply_styles()
	_refresh()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	# Center text/totem.
	_glyph_label = Label.new()
	_glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph_label.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_glyph_label.add_theme_font_size_override("font_size", DesignTokens.FS_LG)
	_glyph_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	add_child(_glyph_label)

	_totem = TotemHelper.new()
	_totem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_totem.offset_left = 8
	_totem.offset_top = 8
	_totem.offset_right = -8
	_totem.offset_bottom = -8
	_totem.visible = false
	add_child(_totem)

	# Cooldown progress bar — bottom of slot, inset from rounded corners.
	_cd_progress = Panel.new()
	_cd_progress.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cd_progress.offset_left = 6
	_cd_progress.offset_right = -6
	_cd_progress.offset_top = -6
	_cd_progress.offset_bottom = -3
	_cd_progress.visible = false
	add_child(_cd_progress)

	# Key chip — small overlay above-left corner.
	_key_panel = PanelContainer.new()
	_key_panel.custom_minimum_size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	_key_panel.position = Vector2(-6, -6)
	_key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key_panel)

	_key_text = Label.new()
	_key_text.text = _key_label
	_key_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_text.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_key_text.add_theme_font_size_override("font_size", 9)
	_key_text.add_theme_color_override("font_color", DesignTokens.FG_3)
	_key_panel.add_child(_key_text)

func _apply_styles() -> void:
	add_theme_stylebox_override("panel", _build_slot_box())
	if _key_panel != null:
		_key_panel.add_theme_stylebox_override("panel", DesignTokens.key_chip_box())

func _build_slot_box() -> StyleBoxFlat:
	# Locked slots get a softer fill + dashed-feel border (same hairline,
	# half alpha) so the eye reads them as deliberately empty.
	if _locked:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(DesignTokens.NIGHT_2.r, DesignTokens.NIGHT_2.g,
			DesignTokens.NIGHT_2.b, 0.55)
		sb.set_corner_radius_all(DesignTokens.RADIUS_2)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.04)
		return sb
	return DesignTokens.slot_panel_box()

func configure(key_label: String, hero_id: String,
		show_totem_when_ready: bool = false, locked: bool = false) -> void:
	_key_label = key_label
	_hero_id = hero_id
	_show_totem_when_ready = show_totem_when_ready
	_locked = locked
	if _key_text != null:
		_key_text.text = key_label
	_apply_styles()
	_refresh()

func set_glyph_text(text: String) -> void:
	_glyph = text
	_refresh()

func set_cooldown(remaining: float, maximum: float) -> void:
	_cooldown = max(0.0, remaining)
	_cooldown_max = max(0.0, maximum)
	_refresh()

func set_hero(hero_id: String) -> void:
	_hero_id = hero_id
	_refresh()

func _refresh() -> void:
	if _glyph_label == null:
		return
	var on_cd := _cooldown > 0.0
	if _locked:
		# Reserved-for-future state. Em-dash glyph at low contrast keeps the
		# slot legible without claiming it's interactive.
		_totem.visible = false
		_cd_progress.visible = false
		_glyph_label.visible = true
		_glyph_label.text = "—"
		_glyph_label.add_theme_color_override("font_color", DesignTokens.FG_3)
		modulate = Color(1, 1, 1, 0.55)
		return
	if on_cd:
		_glyph_label.visible = true
		_glyph_label.text = str(int(ceil(_cooldown)))
		_glyph_label.add_theme_color_override("font_color", DesignTokens.FG_2)
		_totem.visible = false
		# Dim slot.
		modulate = Color(1, 1, 1, 0.78)
	else:
		modulate = Color(1, 1, 1, 1)
		if _show_totem_when_ready and DesignTokens.totem_texture(_hero_id) != null:
			_totem.visible = true
			_totem.set_faction(_hero_id)
			_glyph_label.visible = false
		else:
			_totem.visible = false
			_glyph_label.visible = true
			_glyph_label.text = _glyph
			_glyph_label.add_theme_color_override(
				"font_color", DesignTokens.core_color(_hero_id),
			)
	# Cooldown progress strip — drawn under the slot's text.
	if _cd_progress != null:
		_cd_progress.visible = on_cd and _cooldown_max > 0.0
		if _cd_progress.visible:
			var ratio: float = clamp(1.0 - (_cooldown / _cooldown_max), 0.0, 1.0)
			# Two-stylebox trick: track + fill via a single inner Panel sized
			# to ratio. Easier here: use modulate-on-fill via a child rect.
			# We render the fill as a flat Color2D background on the panel
			# itself (track color), with a child filling its width.
			_cd_progress.add_theme_stylebox_override("panel", _cd_track_box())
			# Spawn fill child once.
			if _cd_progress.get_child_count() == 0:
				var fill := Panel.new()
				fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
				fill.offset_top = 0
				fill.offset_bottom = 0
				_cd_progress.add_child(fill)
			var fill_node: Panel = _cd_progress.get_child(0)
			fill_node.add_theme_stylebox_override("panel", _cd_fill_box())
			fill_node.offset_right = _cd_progress.size.x * ratio
			# Defer width application until the parent has been sized once.
			if _cd_progress.size.x <= 0.0:
				_cd_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				call_deferred("_refresh")

func _cd_track_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.NIGHT_3
	sb.set_corner_radius_all(2)
	return sb

func _cd_fill_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := DesignTokens.core_color(_hero_id)
	sb.bg_color = Color(c.r, c.g, c.b, 0.85)
	sb.set_corner_radius_all(2)
	return sb
