extends Control
##
## Win/loss screen. Three buttons: "Try again" (same hero, fresh run),
## "Visit the lodge" (open meta-progression UI), and "Change hero" (back to
## hero select). Copy follows the voice rules from README.md (sentence case,
## no emoji, warm but not ironic).

signal restart_requested()
signal change_hero_requested()
signal lodge_requested()

var _is_victory: bool = true
var _tokens_earned: int = 0

func show_victory(tokens_earned: int = 0) -> void:
	_is_victory = true
	_tokens_earned = tokens_earned
	visible = true
	queue_redraw()

func show_defeat(tokens_earned: int = 0) -> void:
	_is_victory = false
	_tokens_earned = tokens_earned
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
		elif _lodge_rect().has_point(event.position):
			lodge_requested.emit()
		elif _change_rect().has_point(event.position):
			change_hero_requested.emit()

func _draw() -> void:
	# Curtain.
	draw_rect(Rect2(Vector2.ZERO, size), Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.85), true)
	var font := ThemeDB.fallback_font
	# Headline.
	var headline := "Run complete." if _is_victory else "Run ended."
	var sub := "We held." if _is_victory else "The line broke."
	var headline_w := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL).x
	draw_string(font, Vector2((size.x - headline_w) * 0.5, size.y * 0.36),
		headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL, DesignTokens.FG_1)
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, Vector2((size.x - sub_w) * 0.5, size.y * 0.36 + 48),
		sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, DesignTokens.FG_2)
	# Token reward — only render when there's something to report. Phrasing
	# leans warm; "earned" beats "+N" because it reads as a felt outcome.
	if _tokens_earned > 0:
		var reward := "%d %s earned for the lodge." % [
			_tokens_earned,
			"token" if _tokens_earned == 1 else "tokens",
		]
		var reward_w := font.get_string_size(reward, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
		draw_string(font, Vector2((size.x - reward_w) * 0.5, size.y * 0.36 + 92),
			reward, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, DesignTokens.GOLD_COIN)
	# Buttons. Primary keeps the player in the run with the same hero; lodge
	# is the meta-progression detour; secondary returns to hero select.
	var accent := DesignTokens.core_color(GameState.hero_id)
	_draw_button(_restart_rect(), "Try again", accent, font, true)
	_draw_button(_lodge_rect(), "Visit the lodge", accent, font, false)
	_draw_button(_change_rect(), "Change hero", accent, font, false)

func _draw_button(rect: Rect2, label: String, accent: Color, font: Font, primary: bool) -> void:
	draw_rect(rect, DesignTokens.NIGHT_2, true)
	draw_rect(rect, accent, false, 2.0 if primary else 1.0)
	var label_color := DesignTokens.FG_1 if primary else DesignTokens.FG_2
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 8),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, label_color)

func _restart_rect() -> Rect2:
	var w := 240.0
	var h := 56.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6, w, h)

func _lodge_rect() -> Rect2:
	var w := 240.0
	var h := 48.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6 + 72, w, h)

func _change_rect() -> Rect2:
	var w := 240.0
	var h := 48.0
	return Rect2((size.x - w) * 0.5, size.y * 0.6 + 132, w, h)
