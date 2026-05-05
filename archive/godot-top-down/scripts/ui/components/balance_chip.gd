extends PanelContainer
##
## BalanceChip — compact "BALANCE / N coin" chip that sits next to the
## HeroBadge. Not in the canonical hi-fi v3 spec (the JSX shows balance in
## the prep BuildDrawer instead) but we need it on the in-run HUD because
## v0 plays cards live during the wave and the player can't spend without
## seeing the number.
##
## Public API:
##   - set_balance(coin)

var _coin: int = 0
var _eyebrow: Label
var _value: Label

func _ready() -> void:
	_build()
	_apply_styles()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(124, 56)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	add_child(col)

	_eyebrow = Label.new()
	_eyebrow.text = "BALANCE"
	_eyebrow.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_eyebrow.add_theme_font_size_override("font_size", 10)
	_eyebrow.add_theme_color_override("font_color", DesignTokens.FG_3)
	col.add_child(_eyebrow)

	_value = Label.new()
	_value.text = "0 coin"
	_value.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_value.add_theme_font_size_override("font_size", DesignTokens.FS_LG)
	_value.add_theme_color_override("font_color", DesignTokens.GOLD_COIN)
	col.add_child(_value)

func _apply_styles() -> void:
	var border := Color(DesignTokens.GOLD_COIN.r, DesignTokens.GOLD_COIN.g,
		DesignTokens.GOLD_COIN.b, 0.45)
	var box := DesignTokens.card_panel_box(border, 1)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)

func set_balance(coin: int) -> void:
	_coin = coin
	if _value != null:
		_value.text = "%d coin" % coin
