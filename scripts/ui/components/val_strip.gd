extends PanelContainer
##
## ValStrip — bottom-center HUD strip. Mirrors `design/src/components.jsx`
## `ValStrip` 1:1 (cream puck + name "Val" + status sub).
##
## Public API:
##   - set_status(text)

const TotemHelper := preload("res://scripts/ui/components/totem_image.gd")

const PUCK_SIZE := 36

var _name_label: Label
var _status_label: Label
var _puck: PanelContainer
var _totem: Control

func _ready() -> void:
	_build()
	_apply_styles()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_puck = PanelContainer.new()
	_puck.custom_minimum_size = Vector2(PUCK_SIZE, PUCK_SIZE)
	_puck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_puck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_puck)

	_totem = TotemHelper.new()
	_totem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_totem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_puck.add_child(_totem)
	_totem.set_faction("Val")

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	_name_label = Label.new()
	_name_label.text = "Val"
	_name_label.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_name_label.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	_name_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	col.add_child(_name_label)

	_status_label = Label.new()
	_status_label.text = "scanning the line"
	_status_label.add_theme_font_override("font", DesignTokens.font_body())
	_status_label.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	_status_label.add_theme_color_override("font_color", DesignTokens.FG_3)
	col.add_child(_status_label)

func _apply_styles() -> void:
	# Card-style panel; matches `.val-strip` (radius-3, hairline).
	var box := DesignTokens.card_panel_box(Color(1, 1, 1, 0.06), 1)
	box.content_margin_left = 8
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)
	# Puck — Val merle wash with a hairline. Matches `.vs-puck`.
	var puck_box := DesignTokens.panel_box(
		Color(DesignTokens.VAL_MERLE.r, DesignTokens.VAL_MERLE.g, DesignTokens.VAL_MERLE.b, 0.18),
		DesignTokens.RADIUS_2,
		Color(1, 1, 1, 0.08), 1,
	)
	puck_box.content_margin_left = 4
	puck_box.content_margin_right = 4
	puck_box.content_margin_top = 4
	puck_box.content_margin_bottom = 4
	if _puck != null:
		_puck.add_theme_stylebox_override("panel", puck_box)

func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
