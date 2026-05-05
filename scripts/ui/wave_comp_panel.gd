extends Control
##
## Private side panel — first-hit player only sees the live wave composition
## here (hi-fi v3 §2A/2B + signoff: info-asymmetry leak fix). Teammates see
## only the coarse "in combat" pip on their HeroBadge.
##
## In v0.1 single-player the local hero is always the first-hit player, so
## the panel surfaces on wave_started and clears on wave_ended. The full
## info-asymmetry rendering (peer "coarse 3-block bar + qualitative label"
## fallback) is M4 — this script ships the component; the multiplayer
## wiring lands later.

const SAFE_INSET := 24.0
const PANEL_WIDTH := 244.0
const PANEL_HEIGHT := 196.0

var _composition: Dictionary = {}
var _hero_id: String = "Buffalo"
var _round_index: int = 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

func show_for(round_index: int, composition: Dictionary, hero_id: String) -> void:
	# `composition` is a Waves.ROUNDS entry — `{name, enemies: [{type, count}]}`.
	_round_index = round_index
	_composition = composition
	_hero_id = hero_id
	visible = true
	queue_redraw()

func hide_panel() -> void:
	visible = false

func _draw() -> void:
	if not visible:
		return
	# Anchored top-right under the WavePill + low-core-chip tower so it never
	# fights for the same eye-line as the wave imperative.
	var origin := Vector2(
		size.x - SAFE_INSET - PANEL_WIDTH,
		SAFE_INSET + 64.0 + 8.0 + 44.0 + 8.0 + 26.0 + 8.0,
	)
	var rect := Rect2(origin, Vector2(PANEL_WIDTH, PANEL_HEIGHT))
	# Body — night-1 with hero-core 0.45a hairline; matches WavePill voice.
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.92)
	draw_rect(rect, bg, true)
	draw_rect(rect, DesignTokens.hero_core_border(_hero_id), false, 1.0)
	var inner_x := rect.position.x + 16.0
	# Eyebrow — ALL CAPS per voice rule.
	_draw_label("WAVE %d COMPOSITION" % _round_index,
		Vector2(inner_x, rect.position.y + 12.0),
		DesignTokens.core_color(_hero_id), DesignTokens.FS_XS)
	# Round name in sentence case (e.g. "Probe", "Pressure", "Heavy charge").
	var round_name: String = _composition.get("name", "")
	if round_name != "":
		_draw_label(round_name, Vector2(inner_x, rect.position.y + 30.0),
			DesignTokens.FG_1, DesignTokens.FS_LG)
	# Enemy roster — type · count rows.
	var enemies: Array = _composition.get("enemies", [])
	var row_y := rect.position.y + 64.0
	for entry in enemies:
		var line := "%s · %d" % [_human_readable(entry.type), int(entry.count)]
		_draw_label(line, Vector2(inner_x, row_y),
			DesignTokens.FG_2, DesignTokens.FS_SM)
		row_y += 22.0
	# Footnote — only the local player sees this; teammates get the coarse
	# pip + label per the info-asymmetry rule. Reads as a soft caption.
	_draw_label("Visible to you only.",
		Vector2(inner_x, rect.end.y - 22.0),
		DesignTokens.FG_3, DesignTokens.FS_XS)

func _human_readable(enemy_type: String) -> String:
	# Convert PascalCase ids ("GruntMelee") to sentence-cased labels
	# ("Grunt melee") so the panel obeys the body voice rule.
	if enemy_type.is_empty():
		return ""
	var parts: PackedStringArray = []
	var current := ""
	for i in enemy_type.length():
		var ch := enemy_type[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			parts.append(current)
			current = ""
		current += ch
	parts.append(current)
	if parts.is_empty():
		return enemy_type
	var head: String = parts[0]
	var tail_parts: PackedStringArray = []
	for j in range(1, parts.size()):
		tail_parts.append(parts[j].to_lower())
	if tail_parts.is_empty():
		return head
	return "%s %s" % [head, " ".join(tail_parts)]

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
