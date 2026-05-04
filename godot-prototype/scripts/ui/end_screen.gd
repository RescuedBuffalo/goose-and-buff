extends Control
##
## Win/loss screen. Single button to restart. Copy follows the voice rules
## from README.md (sentence case, no emoji, warm but not ironic).

signal restart_requested()

var _is_victory: bool = true

func show_victory() -> void:
	_is_victory = true
	visible = true
	queue_redraw()

func show_defeat() -> void:
	_is_victory = false
	visible = true
	queue_redraw()

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rect := _restart_rect()
		if rect.has_point(event.position):
			restart_requested.emit()

func _draw() -> void:
	# Curtain.
	draw_rect(Rect2(Vector2.ZERO, size), Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.85), true)
	var font := ThemeDB.fallback_font
	# Headline.
	var headline := "Run complete." if _is_victory else "Run ended."
	var sub := "We held." if _is_victory else "The line broke."
	var headline_w := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL).x
	draw_string(font, Vector2((size.x - headline_w) * 0.5, size.y * 0.4),
		headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL, DesignTokens.FG_1)
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, Vector2((size.x - sub_w) * 0.5, size.y * 0.4 + 48),
		sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, DesignTokens.FG_2)
	# Restart button.
	var rect := _restart_rect()
	draw_rect(rect, DesignTokens.NIGHT_2, true)
	draw_rect(rect, DesignTokens.BUFFALO_CORE, false, 2.0)
	var label := "Try again"
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 8),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, DesignTokens.FG_1)

func _restart_rect() -> Rect2:
	var w := 220.0
	var h := 56.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6, w, h)
