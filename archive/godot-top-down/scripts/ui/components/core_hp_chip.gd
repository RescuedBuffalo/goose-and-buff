extends PanelContainer
##
## CoreHpChip / low-core chip — the "Core 80 / 200" alert that appears when
## the local sector core drops below 50%. Mirrors `CoreHpChip` in
## design/src/components.jsx.
##
## Public API:
##   - set_core(current, max)
##   - hide_chip()

var _current: float = 0.0
var _max: float = 0.0

var _eyebrow: Label
var _bar: PanelContainer
var _fill: Panel
var _value: Label

func _ready() -> void:
	_build()
	_apply_styles()
	visible = false

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_eyebrow = Label.new()
	_eyebrow.text = "YOUR CORE"
	_eyebrow.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_eyebrow.add_theme_font_size_override("font_size", 9)
	_eyebrow.add_theme_color_override("font_color", DesignTokens.HELP_INK)
	_eyebrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_eyebrow)

	_bar = PanelContainer.new()
	_bar.custom_minimum_size = Vector2(80, 5)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.clip_contents = true
	row.add_child(_bar)

	_fill = Panel.new()
	_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_bar.add_child(_fill)

	_value = Label.new()
	_value.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_value.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	_value.add_theme_color_override("font_color", DesignTokens.HELP_INK)
	_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_value)

func _apply_styles() -> void:
	var box := DesignTokens.panel_box(
		DesignTokens.CORE_FELL_BG, 999, DesignTokens.CORE_FELL_LINE, 1,
	)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	add_theme_stylebox_override("panel", box)
	# Bar track + fill.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.50)
	track.set_corner_radius_all(3)
	if _bar != null:
		_bar.add_theme_stylebox_override("panel", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = DesignTokens.HP_CRIT
	fill.set_corner_radius_all(2)
	if _fill != null:
		_fill.add_theme_stylebox_override("panel", fill)

func set_core(current: float, hp_max: float) -> void:
	_current = max(0.0, current)
	_max = max(0.0, hp_max)
	if _max <= 0.0:
		visible = false
		return
	visible = true
	var ratio: float = clamp(_current / _max, 0.0, 1.0)
	_value.text = "%d%%" % int(ratio * 100.0)
	_apply_fill.call_deferred(ratio)

func _apply_fill(ratio: float) -> void:
	if _bar == null or _fill == null:
		return
	var w: float = _bar.size.x
	if w <= 0.0:
		_apply_fill.call_deferred(ratio)
		return
	_fill.offset_right = w * ratio

func hide_chip() -> void:
	visible = false
