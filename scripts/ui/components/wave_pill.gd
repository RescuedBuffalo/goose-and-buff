extends PanelContainer
##
## WavePill — top-right HUD pill. Mirrors `design/src/components.jsx`
## `WavePill` 1:1 (eyebrow + headline on the left, divider, mono timer on
## the right). Pill-shaped via `--radius-pill`.
##
## Public API:
##   - set_phase(phase, round_index, hero_id)
##   - set_prep_seconds(seconds_left)
##   - set_headline(text)        → override the headline (low-core empathy etc.)
##   - set_eyebrow(text)         → override the eyebrow

var _phase: String = "Prep"
var _round_index: int = 1
var _hero_id: String = "Buffalo"
var _prep_seconds: float = 0.0
var _headline_override: String = ""
var _eyebrow_override: String = ""

# Locked verbatim copy from hi-fi v3 §2A/2B. Cycled per wave so back-to-back
# rounds don't repeat.
const HEADLINES_WAVE := ["Hold steady.", "Stay sharp."]
var _wave_voice_index := 0

# Children
var _eyebrow_label: Label
var _headline_label: Label
var _divider: ColorRect
var _timer_label: Label

func _ready() -> void:
	_build()
	_apply_styles()
	_refresh()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(380, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)

	# Left column: eyebrow + headline.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	_eyebrow_label = Label.new()
	_eyebrow_label.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_eyebrow_label.add_theme_font_size_override("font_size", 10)
	_eyebrow_label.add_theme_color_override("font_color", DesignTokens.FG_3)
	col.add_child(_eyebrow_label)

	_headline_label = Label.new()
	_headline_label.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_headline_label.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	_headline_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	col.add_child(_headline_label)

	# Divider — vertical hairline.
	_divider = ColorRect.new()
	_divider.color = Color(1, 1, 1, 0.12)
	_divider.custom_minimum_size = Vector2(1, 28)
	_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_divider)

	# Right: mono timer.
	_timer_label = Label.new()
	_timer_label.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_timer_label.add_theme_font_size_override("font_size", DesignTokens.FS_XL)
	_timer_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	_timer_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_timer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_label.custom_minimum_size = Vector2(72, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_timer_label)

func _apply_styles() -> void:
	add_theme_stylebox_override("panel", DesignTokens.pill_panel_box())

func set_phase(phase: String, round_index: int, hero_id: String) -> void:
	_phase = phase
	_round_index = round_index
	_hero_id = hero_id
	_refresh()

func set_prep_seconds(seconds_left: float) -> void:
	_prep_seconds = seconds_left
	_refresh()

func set_headline(text: String) -> void:
	_headline_override = text
	_refresh()

func set_eyebrow(text: String) -> void:
	_eyebrow_override = text
	_refresh()

func cycle_wave_voice() -> void:
	_wave_voice_index = (_wave_voice_index + 1) % HEADLINES_WAVE.size()

func _refresh() -> void:
	if _eyebrow_label == null:
		return
	_eyebrow_label.text = _eyebrow_override if _eyebrow_override != "" else _default_eyebrow()
	_headline_label.text = _headline_override if _headline_override != "" else _default_headline()
	_timer_label.text = _format_timer()
	# Recolor the eyebrow with the hero core during a wave (matches
	# `wave-pill .wp-eyebrow` getting the accent in surface-2 state 2A).
	if _phase == "Wave":
		_eyebrow_label.add_theme_color_override("font_color", DesignTokens.core_color(_hero_id))
	else:
		_eyebrow_label.add_theme_color_override("font_color", DesignTokens.FG_3)

func _default_eyebrow() -> String:
	if _phase == "Wave":
		return "WAVE %d · %s'S WATCH" % [_round_index, _hero_id.to_upper()]
	if _phase == "Debrief":
		return "DEBRIEF · ROUND %d" % _round_index
	return "PREP · ROUND %d" % _round_index

func _default_headline() -> String:
	if _phase == "Prep":
		if _prep_seconds <= 0.0:
			return "Waiting on the watch."
		return "Stay sharp."
	if _phase == "Wave":
		return HEADLINES_WAVE[_wave_voice_index]
	if _phase == "Debrief":
		return "Catch your breath."
	return "Hold the line."

func _format_timer() -> String:
	if _phase == "Prep" and _prep_seconds > 0.0:
		var s: int = int(ceil(_prep_seconds))
		@warning_ignore("integer_division")
		var minutes: int = s / 60
		var rem: int = s % 60
		return "%d:%02d" % [minutes, rem]
	return ""
