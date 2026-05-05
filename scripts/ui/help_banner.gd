extends Control
##
## Help-request banner — single state machine that fires + clears in lockstep
## with the WavePill / HeroBadge pulse (hi-fi v3 §3A). The component lives
## here in v0.1 but is M4-deferred for wiring: there is no real "help
## requested" signal until multiplayer lands. `show_for()` is the public
## entry point; the rest of the codebase doesn't call it yet.
##
## Visual: bottom-center band above the hand strip. Uses the new help-line /
## help-fill / help-ink tokens verbatim.

const SAFE_INSET := 24.0
const HAND_STRIP_HEIGHT := 240.0
const VAL_STRIP_HEIGHT := 52.0

var _calling_hero: String = ""
var _responder_hero: String = ""
var _eta_seconds: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

func show_for(calling_hero: String, responder_hero: String, eta_seconds: float) -> void:
	# `calling_hero` and `responder_hero` are totem ids — never personal
	# names. v0.1 single-player will not call this; M4 will.
	_calling_hero = calling_hero
	_responder_hero = responder_hero
	_eta_seconds = max(0.0, eta_seconds)
	visible = true
	queue_redraw()

func clear_help() -> void:
	visible = false
	_calling_hero = ""
	_responder_hero = ""
	_eta_seconds = 0.0
	queue_redraw()

func _draw() -> void:
	if not visible:
		return
	var band_w := 460.0
	var band_h := 56.0
	# Sit just above the ValStrip so they stack cleanly.
	var origin := Vector2(
		(size.x - band_w) * 0.5,
		size.y - HAND_STRIP_HEIGHT - SAFE_INSET - VAL_STRIP_HEIGHT - 16.0 - band_h,
	)
	var rect := Rect2(origin, Vector2(band_w, band_h))
	# Help fill + line + ink — locked tokens.
	draw_rect(rect, DesignTokens.HELP_FILL, true)
	draw_rect(rect, DesignTokens.HELP_LINE, false, 1.0)
	# Headline reads the verbatim copy from §3A:
	#   "You called — Goose is moving · ETA 4s"
	# Both heroes are totem ids; ETA renders without padding seconds.
	var head: String
	if _responder_hero.is_empty():
		head = "Help on the way."
	else:
		head = "You called — %s is moving · ETA %ds" % [_responder_hero, int(ceil(_eta_seconds))]
	_draw_label(head, rect.position + Vector2(20.0, 18.0),
		DesignTokens.HELP_INK, DesignTokens.FS_MD)

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
