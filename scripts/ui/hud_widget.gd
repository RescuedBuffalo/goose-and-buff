extends Control
##
## v0 HUD per the hi-fi v3 spec (`game1/hifi-v3-signoff.md`).
##
## Four anchor regions live here:
##   - top-left      → HeroBadge stack (one badge in single-player; component
##                     supports peer states for M4 wiring)
##   - top-right     → WavePill (variant per phase; border is hero-core 0.45a)
##   - bottom-center → ValStrip (Val companion status, above the hand strip)
##   - low-core chip → appears when sector core HP drops below 50%
##
## Voice rules: sentence case in body; ALL-CAPS only for eyebrow labels and
## the wave-shout (5A) overlay. HP renders as `124 / 160`, timers as `0:24`,
## totem names only — never personal names or @-handles.
##
## AbilityRail (bottom-left) is its own Control — `scenes/ui/ability_rail.tscn`
## is added to the same UI layer in `main.gd`. The wave-shout overlay still
## piggybacks on this widget so its z-order stays correct relative to the pill.

const SAFE_INSET := 24.0
const HAND_STRIP_HEIGHT := 240.0
const CORE_LOW_THRESHOLD := 0.5  # AC: HUD chip appears when local core < 50%.

const BADGE_SIZE := Vector2(248.0, 64.0)
const PILL_PADDING := Vector2(20.0, 14.0)
const VAL_STRIP_HEIGHT := 52.0

var _coin: int = 0
var _round_index: int = 1
var _prep_seconds: float = 0.0
var _phase_label: String = "Prep"
var _wave_banner: String = ""
var _wave_banner_timeout: float = 0.0
# Compositional flavor for the WavePill — alternates between locked verbatim
# voice lines per phase (hi-fi v3 §2A/2B). Cycled on wave_started so back-to-
# back rounds don't repeat the same imperative.
var _wave_voice_index: int = 0
const _WAVE_HEADLINES := ["Hold steady.", "Stay sharp."]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.hero_hp_changed.connect(func(_a, _b): queue_redraw())
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.retreat_changed.connect(func(_active): queue_redraw())
	set_process(true)

func bind(economy, wave_director, sector) -> void:
	economy.balance_changed.connect(_on_coin_changed)
	wave_director.round_started.connect(_on_round_started)
	wave_director.prep_timer_changed.connect(_on_prep_timer_changed)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	sector.core_hp_changed.connect(func(_a, _b): queue_redraw())
	_coin = economy.balance

func _process(delta: float) -> void:
	if _wave_banner_timeout > 0.0:
		_wave_banner_timeout -= delta
		if _wave_banner_timeout <= 0.0:
			_wave_banner = ""
		queue_redraw()

func _on_coin_changed(new_balance: int) -> void:
	_coin = new_balance
	queue_redraw()

func _on_round_started(round_index: int) -> void:
	_round_index = round_index
	_phase_label = "Prep"
	queue_redraw()

func _on_prep_timer_changed(seconds_left: float) -> void:
	_prep_seconds = seconds_left
	queue_redraw()

func _on_phase_changed(phase: String) -> void:
	match phase:
		"prep": _phase_label = "Prep"
		"wave": _phase_label = "Wave"
		"debrief": _phase_label = "Debrief"
		_: _phase_label = phase.capitalize()
	queue_redraw()

func _on_wave_started(round_index: int, _composition: Dictionary) -> void:
	# Wave-shout banner — the one exemption from sentence case (hi-fi v3 §5A).
	_wave_banner = "WAVE %d — HOLD THE LINE" % round_index
	_wave_banner_timeout = 2.4
	_wave_voice_index = (_wave_voice_index + 1) % _WAVE_HEADLINES.size()
	queue_redraw()

func show_banner(text: String, duration: float) -> void:
	_wave_banner = text
	_wave_banner_timeout = duration
	queue_redraw()

func _on_wave_ended(_idx: int, victory: bool) -> void:
	# Param prefixed with `_` would normally signal "unused", but a leading-
	# underscore name still shadows the class member `_round_index` under 4.6.
	_wave_banner = "We held." if victory else "The line broke."
	_wave_banner_timeout = 3.0
	queue_redraw()

# ─── Draw entry ───────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_hero_badge_stack()
	_draw_wave_pill()
	_draw_val_strip()
	_draw_low_core_chip()
	_draw_retreat_hint()
	_draw_wave_shout()

# ─── HeroBadge ────────────────────────────────────────────────────────────

func _draw_hero_badge_stack() -> void:
	# v0.1 single-player: render the local hero only. Stack origin is the
	# top-left safe-inset corner; M4 will append peer badges below.
	var origin := Vector2(SAFE_INSET, SAFE_INSET)
	_draw_hero_badge(GameState.hero_id, origin, true)

func _draw_hero_badge(hero_id: String, origin: Vector2, is_local: bool) -> void:
	var rect := Rect2(origin, BADGE_SIZE)
	var hp := GameState.hero_hp
	var hp_max := GameState.hero_hp_max
	var hero_downed: bool = hp <= 0.0 and hp_max > 0.0
	var hp_ratio: float = 0.0 if hp_max == 0.0 else hp / hp_max
	# Card background — night-1 with hairline border (hero-core 0.45a) and a
	# faction-tinted "lantern" strip at the totem side.
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.92)
	draw_rect(rect, bg, true)
	var lantern_rect := Rect2(rect.position, Vector2(BADGE_SIZE.y, BADGE_SIZE.y))
	draw_rect(lantern_rect, DesignTokens.lantern_color(hero_id), true)
	var border := DesignTokens.hero_core_border(hero_id)
	draw_rect(rect, border, false, 1.0)
	# Totem puck — solid floor tint, ink-colored letter glyph centered.
	var puck_inset := 10.0
	var puck_rect := Rect2(
		rect.position + Vector2(puck_inset, puck_inset),
		Vector2(BADGE_SIZE.y - puck_inset * 2.0, BADGE_SIZE.y - puck_inset * 2.0),
	)
	draw_rect(puck_rect, DesignTokens.floor_color(hero_id), true)
	var glyph := "" if hero_id.is_empty() else hero_id.substr(0, 1)
	_draw_centered(glyph, puck_rect, DesignTokens.ink_color(hero_id), DesignTokens.FS_LG)
	# Body column — name (sentence case totem) + HP bar + numeric HP.
	var body_x := rect.position.x + BADGE_SIZE.y + 8.0
	var body_w := rect.size.x - (BADGE_SIZE.y + 8.0) - 12.0
	_draw_label(hero_id, Vector2(body_x, rect.position.y + 8.0), DesignTokens.FG_1, DesignTokens.FS_MD)
	# In-combat pip (M4: peers see this on remote players' badges; for the
	# local player we light it during a wave so the component reads correctly).
	if is_local and _phase_label == "Wave":
		var pip_w := 56.0
		var pip_h := 14.0
		var pip_rect := Rect2(
			Vector2(rect.end.x - pip_w - 10.0, rect.position.y + 8.0),
			Vector2(pip_w, pip_h),
		)
		draw_rect(pip_rect, DesignTokens.PIP_COMBAT_BG, true)
		_draw_centered("In combat", pip_rect, DesignTokens.PIP_COMBAT_FG, DesignTokens.FS_XS)
	# HP track + fill.
	var bar_rect := Rect2(
		Vector2(body_x, rect.position.y + BADGE_SIZE.y - 22.0),
		Vector2(body_w * 0.62, 6.0),
	)
	draw_rect(bar_rect, DesignTokens.NIGHT_3, true)
	var fill_w: float = bar_rect.size.x * clamp(hp_ratio, 0.0, 1.0)
	if fill_w > 0.0:
		var hp_color: Color = DesignTokens.HP_CRIT if hero_downed else DesignTokens.hp_color(hp_ratio)
		draw_rect(Rect2(bar_rect.position, Vector2(fill_w, bar_rect.size.y)), hp_color, true)
	# Numeric HP — `124 / 160` per voice rules; "Downed" while at 0.
	var hp_text: String = "Downed" if hero_downed else "%d / %d" % [int(hp), int(hp_max)]
	var hp_color_text: Color = DesignTokens.HP_CRIT if hero_downed else DesignTokens.FG_2
	_draw_label(
		hp_text,
		Vector2(bar_rect.end.x + 10.0, rect.position.y + BADGE_SIZE.y - 30.0),
		hp_color_text,
		DesignTokens.FS_SM,
	)

# ─── WavePill ─────────────────────────────────────────────────────────────

func _draw_wave_pill() -> void:
	# Variant copy follows hi-fi v3 §2A/2B verbatim. Border rule: always
	# 1px hero-core 0.45a; only fill / glow vary by variant.
	var hero_id := GameState.hero_id
	var pill_w := 268.0
	var pill_h := 64.0
	var origin := Vector2(size.x - SAFE_INSET - pill_w, SAFE_INSET)
	var rect := Rect2(origin, Vector2(pill_w, pill_h))
	# Body — night-1 fill, faint scrim glow when wave is hot.
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.88)
	draw_rect(rect, bg, true)
	if _phase_label == "Wave":
		# 2A glow — soft hero-core wash on the inner panel.
		var core := DesignTokens.core_color(hero_id)
		var glow := Color(core.r, core.g, core.b, 0.07)
		draw_rect(rect, glow, true)
	draw_rect(rect, DesignTokens.hero_core_border(hero_id), false, 1.0)
	# Eyebrow — ALL CAPS, locked verbatim.
	var eyebrow := _wave_pill_eyebrow()
	var headline := _wave_pill_headline()
	var timer := _wave_pill_timer()
	var inner_x := rect.position.x + PILL_PADDING.x
	_draw_label(eyebrow, Vector2(inner_x, rect.position.y + 10.0),
		DesignTokens.core_color(hero_id), DesignTokens.FS_XS)
	_draw_label(headline, Vector2(inner_x, rect.position.y + 30.0),
		DesignTokens.FG_1, DesignTokens.FS_LG)
	if timer != "":
		var font := ThemeDB.fallback_font
		var tw: float = font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XL).x
		_draw_label(timer,
			Vector2(rect.end.x - PILL_PADDING.x - tw, rect.position.y + 18.0),
			DesignTokens.core_color(hero_id), DesignTokens.FS_XL)

func _wave_pill_eyebrow() -> String:
	# Eyebrow labels are ALL-CAPS by voice rule. Round number and hero totem
	# are sentence-relevant facts, so we keep them in the eyebrow itself.
	if _phase_label == "Wave":
		return "WAVE %d · %s'S WATCH" % [_round_index, GameState.hero_id.to_upper()]
	if _phase_label == "Debrief":
		return "DEBRIEF · ROUND %d" % _round_index
	return "PREP · ROUND %d" % _round_index

func _wave_pill_headline() -> String:
	# Locked verbatim copy from hi-fi v3 sign-off:
	#   1A "Waiting on the watch." (no countdown — private/quickplay split)
	#   1B "Stay sharp."           (prep with countdown active)
	#   2A "Hold steady."          (wave engaged)
	#   2B "Stay sharp."           (alternate; cycled per wave)
	#   5D "The line broke."       (run defeat)
	if _phase_label == "Prep":
		if _prep_seconds <= 0.0:
			return "Waiting on the watch."
		return "Stay sharp."
	if _phase_label == "Wave":
		# Low-HP override (hi-fi v3 §2C) — empathetic at low core HP.
		var core_ratio: float = 0.0
		if GameState.core_hp_max > 0.0:
			core_ratio = GameState.core_hp / GameState.core_hp_max
		if core_ratio > 0.0 and core_ratio < 0.25:
			return "Your core's hurting."
		return _WAVE_HEADLINES[_wave_voice_index]
	if _phase_label == "Debrief":
		return "Catch your breath."
	return "Hold the line."

func _wave_pill_timer() -> String:
	# Timer renders only during prep — wave phase has no timer per spec.
	if _phase_label == "Prep" and _prep_seconds > 0.0:
		return _format_timer(_prep_seconds)
	return ""

# ─── ValStrip ─────────────────────────────────────────────────────────────

func _draw_val_strip() -> void:
	# Bottom-center, sitting just above the hand strip. Status copy is
	# in-character for Val (the shared Australian Shepherd companion).
	var strip_w := 280.0
	var strip_h := VAL_STRIP_HEIGHT
	var origin := Vector2(
		(size.x - strip_w) * 0.5,
		size.y - HAND_STRIP_HEIGHT - SAFE_INSET - strip_h,
	)
	var rect := Rect2(origin, Vector2(strip_w, strip_h))
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.88)
	draw_rect(rect, bg, true)
	# Cream-tinted hairline matches the val-cream token rather than a hero
	# core (Val isn't a faction, she's the through-line).
	var hairline := Color(DesignTokens.VAL_CREAM.r, DesignTokens.VAL_CREAM.g, DesignTokens.VAL_CREAM.b, 0.30)
	draw_rect(rect, hairline, false, 1.0)
	# Puck.
	var puck_rect := Rect2(rect.position + Vector2(8.0, 8.0), Vector2(strip_h - 16.0, strip_h - 16.0))
	draw_rect(puck_rect, DesignTokens.VAL_CREAM, true)
	_draw_centered("V", puck_rect, DesignTokens.VAL_RUST, DesignTokens.FS_LG)
	# Name + status — sentence case, totem only.
	var text_x := puck_rect.end.x + 10.0
	_draw_label("Val", Vector2(text_x, rect.position.y + 6.0), DesignTokens.FG_1, DesignTokens.FS_MD)
	_draw_label(_val_status(), Vector2(text_x, rect.position.y + strip_h - 22.0),
		DesignTokens.FG_3, DesignTokens.FS_SM)

func _val_status() -> String:
	# v0 placeholder — Val isn't simulated yet (M3 work). Status reads
	# in-character per voice rules; no totem name appears here.
	if _phase_label == "Wave":
		return "circling the line · ready"
	if _phase_label == "Debrief":
		return "catching her breath"
	return "scanning the line"

# ─── Low-core chip ────────────────────────────────────────────────────────

func _draw_low_core_chip() -> void:
	# AC: chip appears only when local core HP drops below 50%. Otherwise
	# the in-world floater above the core (drawn by sector.gd) is enough.
	if GameState.core_hp_max <= 0.0:
		return
	var ratio := GameState.core_hp / GameState.core_hp_max
	if ratio >= CORE_LOW_THRESHOLD:
		return
	var chip_w := 220.0
	var chip_h := 44.0
	# Anchored just below the WavePill so the eye finds it without scanning.
	var origin := Vector2(size.x - SAFE_INSET - chip_w, SAFE_INSET + 64.0 + 8.0)
	var rect := Rect2(origin, Vector2(chip_w, chip_h))
	# Fell vs. hurt — different fills + borders, locked tokens.
	var fell := GameState.core_hp <= 0.0
	var bg: Color = DesignTokens.CORE_FELL_BG if fell else Color(
		DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.92,
	)
	var line: Color = DesignTokens.CORE_FELL_LINE if fell else DesignTokens.HP_CRIT
	draw_rect(rect, bg, true)
	draw_rect(rect, line, false, 1.0)
	var label := "Core fell." if fell else "Core %d / %d" % [int(GameState.core_hp), int(GameState.core_hp_max)]
	_draw_label(label, rect.position + Vector2(14.0, 12.0),
		DesignTokens.FG_1 if fell else DesignTokens.HP_CRIT,
		DesignTokens.FS_MD)

# ─── Retreat hint ────────────────────────────────────────────────────────

func _draw_retreat_hint() -> void:
	# Small mono hint under the WavePill. Replaced by the pulsing badge while
	# the player holds the retreat key — keeps the state unmistakable.
	if GameState.retreat_mode:
		var badge_w := 220.0
		var badge_h := 26.0
		var rect := Rect2(
			Vector2(size.x - SAFE_INSET - badge_w, SAFE_INSET + 64.0 + 8.0 + 50.0),
			Vector2(badge_w, badge_h),
		)
		draw_rect(rect, DesignTokens.HP_CRIT, true)
		draw_rect(rect, DesignTokens.NIGHT_0, false, 1.0)
		_draw_centered("Retreating — units holding fire", rect,
			DesignTokens.NIGHT_0, DesignTokens.FS_XS)
	else:
		var hint := "Hold R to retreat (units ignore enemies)"
		var font := ThemeDB.fallback_font
		var w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM).x
		_draw_label(hint,
			Vector2(size.x - SAFE_INSET - w, SAFE_INSET + 64.0 + 8.0 + 50.0 + 8.0),
			DesignTokens.FG_3, DesignTokens.FS_SM)

# ─── Wave shout overlay ──────────────────────────────────────────────────

func _draw_wave_shout() -> void:
	if _wave_banner == "":
		return
	# Splash band sits above the hand strip; soft scrim under the text.
	var band_h := 80.0
	var band_y := size.y * 0.32
	var band_rect := Rect2(0.0, band_y, size.x, band_h)
	draw_rect(band_rect, DesignTokens.SCRIM_SOFT, true)
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(_wave_banner, HORIZONTAL_ALIGNMENT_CENTER,
		-1, DesignTokens.FS_2XL).x
	draw_string(font,
		Vector2((size.x - tw) * 0.5, band_y + band_h * 0.5 + 12.0),
		_wave_banner, HORIZONTAL_ALIGNMENT_LEFT, -1,
		DesignTokens.FS_2XL, DesignTokens.FG_1)

# ─── Drawing helpers ─────────────────────────────────────────────────────

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_centered(text: String, rect: Rect2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := rect.position + Vector2(
		(rect.size.x - w) * 0.5,
		(rect.size.y + font_size * 0.65) * 0.5,
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _format_timer(seconds: float) -> String:
	var s: int = int(ceil(seconds))
	@warning_ignore("integer_division")
	var minutes: int = s / 60
	var rem: int = s % 60
	return "%d:%02d" % [minutes, rem]
