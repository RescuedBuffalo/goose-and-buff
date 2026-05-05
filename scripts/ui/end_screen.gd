extends Control
##
## Win/loss screen. Two buttons: "Try again" (same hero, fresh run) and
## "Change hero" (back to hero select). Copy follows the voice rules from
## README.md (sentence case, no emoji, warm but not ironic).

signal restart_requested()
signal back_to_lodge_requested()

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
		if _restart_rect().has_point(event.position):
			restart_requested.emit()
		elif _change_rect().has_point(event.position):
			back_to_lodge_requested.emit()

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
	# Buttons. Primary keeps the player in the run with the same hero;
	# secondary returns to hero select for a fresh pick.
	var accent := DesignTokens.core_color(GameState.hero_id)
	_draw_button(_restart_rect(), "Try again", accent, font, true)
	_draw_button(_change_rect(), "Back to the lodge", accent, font, false)

func _draw_button(rect: Rect2, label: String, accent: Color, font: Font, primary: bool) -> void:
	draw_rect(rect, DesignTokens.NIGHT_2, true)
	draw_rect(rect, accent, false, 2.0 if primary else 1.0)
	var label_color := DesignTokens.FG_1 if primary else DesignTokens.FG_2
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 8),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, label_color)

func _restart_rect() -> Rect2:
	var w := 220.0
	var h := 56.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6, w, h)

func _change_rect() -> Rect2:
	var w := 220.0
	var h := 48.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6 + 72, w, h)
