extends Control
##
## v0.1 HUD coordinator. The visual surfaces (HeroBadge, WavePill, ValStrip,
## CoreHpChip, BalanceChip) are now standalone PanelContainer components in
## `scripts/ui/components/`; this script instantiates them at the right
## anchors and forwards GameState / WaveDirector / Sector signals to them.
##
## The wave-shout overlay (transient mid-screen banner) and the hand-strip
## backdrop band still draw via `_draw()` because they're full-width
## scenery rather than discrete panels.

const HeroBadge := preload("res://scripts/ui/components/hero_badge.gd")
const WavePill := preload("res://scripts/ui/components/wave_pill.gd")
const ValStrip := preload("res://scripts/ui/components/val_strip.gd")
const BalanceChip := preload("res://scripts/ui/components/balance_chip.gd")
const CoreHpChip := preload("res://scripts/ui/components/core_hp_chip.gd")

const SAFE_INSET := 32.0
# Hand band: the bottom strip that hosts cards + ability rail + val strip.
# Cards (248 tall + 32 bottom padding) anchor against this.
const HAND_BAND_HEIGHT := 320.0
const HAND_BACKDROP_EXTRA := 0.0
const CARD_TOP_FROM_BOTTOM := 280.0  # CARD_SIZE.y (248) + bottom margin (32)
const VAL_STRIP_HEIGHT := 60.0
const ABILITY_RAIL_HEIGHT := 88.0
const CORE_LOW_THRESHOLD := 0.5
const WAVE_PILL_HEIGHT := 72.0
const WAVE_PILL_WIDTH := 440.0
const HERO_BADGE_WIDTH := 360.0
const HERO_BADGE_HEIGHT := 72.0
const BALANCE_CHIP_WIDTH := 132.0
const BALANCE_CHIP_HEIGHT := 64.0
const PILL_GAP := 8.0
const WAVE_COMP_HEIGHT := 220.0  # mirrors wave_comp_panel.gd's expected size

# Components
var _badge: PanelContainer
var _balance: PanelContainer
var _wave_pill: PanelContainer
var _val_strip: PanelContainer
var _core_chip: PanelContainer
var _retreat_hint: Label

# Transient state
var _phase_label: String = "Prep"
var _round_index: int = 1
var _last_wave_victory: bool = true
var _wave_banner: String = ""
var _wave_banner_timeout: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_components()
	_wire_state_signals()
	set_process(true)

func _build_components() -> void:
	# HeroBadge — top-left.
	_badge = HeroBadge.new()
	add_child(_badge)
	_badge.set_anchor(SIDE_LEFT, 0.0, false)
	_badge.set_anchor(SIDE_RIGHT, 0.0, false)
	_badge.set_anchor(SIDE_TOP, 0.0, false)
	_badge.set_anchor(SIDE_BOTTOM, 0.0, false)
	_badge.offset_left = SAFE_INSET
	_badge.offset_right = SAFE_INSET + HERO_BADGE_WIDTH
	_badge.offset_top = SAFE_INSET
	_badge.offset_bottom = SAFE_INSET + HERO_BADGE_HEIGHT

	# CoreHpChip — small floating chip ABOVE the HeroBadge per the design
	# CSS (`.core-hp-chip { position: absolute; top: -22px; left: 14px }`).
	# Parent it to the badge so it stays attached if the badge ever moves.
	_core_chip = CoreHpChip.new()
	_badge.add_child(_core_chip)
	_core_chip.set_anchor(SIDE_LEFT, 0.0, false)
	_core_chip.set_anchor(SIDE_RIGHT, 0.0, false)
	_core_chip.set_anchor(SIDE_TOP, 0.0, false)
	_core_chip.set_anchor(SIDE_BOTTOM, 0.0, false)
	_core_chip.offset_left = 14.0
	_core_chip.offset_top = -28.0
	_core_chip.offset_right = 14.0 + 220.0
	_core_chip.offset_bottom = 0.0

	# BalanceChip — to the right of the badge.
	_balance = BalanceChip.new()
	add_child(_balance)
	_balance.set_anchor(SIDE_LEFT, 0.0, false)
	_balance.set_anchor(SIDE_RIGHT, 0.0, false)
	_balance.set_anchor(SIDE_TOP, 0.0, false)
	_balance.set_anchor(SIDE_BOTTOM, 0.0, false)
	_balance.offset_left = SAFE_INSET + HERO_BADGE_WIDTH + 12.0
	_balance.offset_right = SAFE_INSET + HERO_BADGE_WIDTH + 12.0 + BALANCE_CHIP_WIDTH
	_balance.offset_top = SAFE_INSET + 4.0
	_balance.offset_bottom = SAFE_INSET + 4.0 + BALANCE_CHIP_HEIGHT

	# WavePill — top-right.
	_wave_pill = WavePill.new()
	add_child(_wave_pill)
	_wave_pill.set_anchor(SIDE_LEFT, 1.0, false)
	_wave_pill.set_anchor(SIDE_RIGHT, 1.0, false)
	_wave_pill.set_anchor(SIDE_TOP, 0.0, false)
	_wave_pill.set_anchor(SIDE_BOTTOM, 0.0, false)
	_wave_pill.offset_left = -(SAFE_INSET + WAVE_PILL_WIDTH)
	_wave_pill.offset_right = -SAFE_INSET
	_wave_pill.offset_top = SAFE_INSET
	_wave_pill.offset_bottom = SAFE_INSET + WAVE_PILL_HEIGHT
	_wave_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# ValStrip — bottom-right corner of the hand band, clear of the cards.
	_val_strip = ValStrip.new()
	add_child(_val_strip)
	_val_strip.set_anchor(SIDE_LEFT, 1.0, false)
	_val_strip.set_anchor(SIDE_RIGHT, 1.0, false)
	_val_strip.set_anchor(SIDE_TOP, 1.0, false)
	_val_strip.set_anchor(SIDE_BOTTOM, 1.0, false)
	_val_strip.offset_left = -(SAFE_INSET + 280.0)
	_val_strip.offset_right = -SAFE_INSET
	_val_strip.offset_top = -(SAFE_INSET + VAL_STRIP_HEIGHT)
	_val_strip.offset_bottom = -SAFE_INSET
	_val_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Retreat hint — small dim mono text under the wave-pill column. Drawn
	# as a Label so font / alignment match the design.
	_retreat_hint = Label.new()
	_retreat_hint.text = "Hold R to retreat (units ignore enemies)"
	_retreat_hint.add_theme_font_override("font", DesignTokens.font_mono())
	_retreat_hint.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	_retreat_hint.add_theme_color_override("font_color", DesignTokens.FG_3)
	_retreat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_retreat_hint.size_flags_horizontal = 0
	add_child(_retreat_hint)
	_retreat_hint.set_anchor(SIDE_LEFT, 1.0, false)
	_retreat_hint.set_anchor(SIDE_RIGHT, 1.0, false)
	_retreat_hint.set_anchor(SIDE_TOP, 0.0, false)
	_retreat_hint.set_anchor(SIDE_BOTTOM, 0.0, false)
	_retreat_hint.offset_left = -(SAFE_INSET + 360.0)
	_retreat_hint.offset_right = -SAFE_INSET
	_retreat_hint.offset_top = SAFE_INSET + WAVE_PILL_HEIGHT + PILL_GAP
	_retreat_hint.offset_bottom = SAFE_INSET + WAVE_PILL_HEIGHT + PILL_GAP + 22.0
	_retreat_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN

func _wire_state_signals() -> void:
	GameState.hero_hp_changed.connect(_on_hero_hp_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.retreat_changed.connect(_on_retreat_changed)
	# Sync any state already published before the HUD existed (the autoload
	# can change before this Control enters the tree).
	_apply_hero_state(GameState.hero_id, GameState.hero_hp, GameState.hero_hp_max)

func bind(economy, wave_director, sector) -> void:
	economy.balance_changed.connect(_on_coin_changed)
	wave_director.round_started.connect(_on_round_started)
	wave_director.prep_timer_changed.connect(_on_prep_timer_changed)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	sector.core_hp_changed.connect(_on_core_hp_changed)
	# Initial sync.
	if _balance != null:
		_balance.set_balance(economy.balance)
	if _core_chip != null:
		_core_chip.set_core(GameState.core_hp, GameState.core_hp_max)
		_apply_low_core_visibility()

# ─── Layout helpers ─────────────────────────────────────────────────────

func _reposition_chips() -> void:
	# CoreHpChip floats above the HeroBadge (parented to it per the design
	# CSS) and the WaveCompPanel now lives in the top-bar middle band, so
	# the retreat hint can sit fixed under the WavePill without any
	# phase-driven shift.
	if _retreat_hint == null:
		return
	var hint_top: float = SAFE_INSET + WAVE_PILL_HEIGHT + PILL_GAP
	_retreat_hint.offset_top = hint_top
	_retreat_hint.offset_bottom = hint_top + 22.0

# ─── Signal handlers ────────────────────────────────────────────────────

func _on_hero_hp_changed(current: float, hp_max: float) -> void:
	_apply_hero_state(GameState.hero_id, current, hp_max)

func _apply_hero_state(hero_id: String, current: float, hp_max: float) -> void:
	if _badge == null:
		return
	_badge.set_hero(hero_id)
	_badge.set_hp(current, hp_max)

func _on_coin_changed(new_balance: int) -> void:
	if _balance != null:
		_balance.set_balance(new_balance)

func _on_round_started(round_index: int) -> void:
	_round_index = round_index
	_phase_label = "Prep"
	_last_wave_victory = true
	if _wave_pill != null:
		_wave_pill.set_phase(_phase_label, _round_index, GameState.hero_id)
	_reposition_chips()

func _on_prep_timer_changed(seconds_left: float) -> void:
	if _wave_pill != null:
		_wave_pill.set_prep_seconds(seconds_left)

func _on_phase_changed(phase: String) -> void:
	match phase:
		"prep": _phase_label = "Prep"
		"wave": _phase_label = "Wave"
		"debrief": _phase_label = "Debrief"
		_: _phase_label = phase.capitalize()
	if _wave_pill != null:
		_wave_pill.set_phase(_phase_label, _round_index, GameState.hero_id)
	if _badge != null:
		_badge.set_combat(_phase_label == "Wave")
	if _val_strip != null:
		_val_strip.set_status(_val_status())
	_reposition_chips()
	queue_redraw()

func _on_wave_started(round_index: int, _composition: Dictionary) -> void:
	_round_index = round_index
	_wave_banner = "WAVE %d — HOLD THE LINE" % round_index
	_wave_banner_timeout = 2.4
	if _wave_pill != null:
		_wave_pill.cycle_wave_voice()
		_wave_pill.set_phase("Wave", _round_index, GameState.hero_id)
	queue_redraw()

func _on_wave_ended(_idx: int, victory: bool) -> void:
	_last_wave_victory = victory
	_wave_banner = "We held." if victory else "The line broke."
	_wave_banner_timeout = 3.0
	if _wave_pill != null:
		_wave_pill.set_headline("Catch your breath." if victory else "The line broke.")
	queue_redraw()

func _on_core_hp_changed(current: float, hp_max: float) -> void:
	if _core_chip != null:
		_core_chip.set_core(current, hp_max)
	_apply_low_core_visibility()
	# Override the WavePill headline with low-core empathy copy when
	# critical.
	if _wave_pill != null and hp_max > 0.0:
		var ratio: float = current / hp_max
		if _phase_label == "Wave" and ratio > 0.0 and ratio < 0.25:
			_wave_pill.set_headline("Your core's hurting.")
		else:
			_wave_pill.set_headline("")

func _apply_low_core_visibility() -> void:
	if _core_chip == null:
		return
	if GameState.core_hp_max <= 0.0:
		_core_chip.visible = false
	else:
		_core_chip.visible = (GameState.core_hp / GameState.core_hp_max) < CORE_LOW_THRESHOLD
	_reposition_chips()

func _on_retreat_changed(active: bool) -> void:
	if _retreat_hint == null:
		return
	if active:
		_retreat_hint.text = "Retreating — units holding fire"
		_retreat_hint.add_theme_color_override("font_color", DesignTokens.HP_CRIT)
	else:
		_retreat_hint.text = "Hold R to retreat (units ignore enemies)"
		_retreat_hint.add_theme_color_override("font_color", DesignTokens.FG_3)

func show_banner(text: String, duration: float) -> void:
	_wave_banner = text
	_wave_banner_timeout = duration
	queue_redraw()

func _val_status() -> String:
	# In-character placeholder — real Val behavior lands in M3.
	if _phase_label == "Wave":
		return "circling the line · ready"
	if _phase_label == "Debrief":
		return "catching his breath"
	return "scanning the line"

# ─── Process / draw ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _wave_banner_timeout > 0.0:
		_wave_banner_timeout -= delta
		if _wave_banner_timeout <= 0.0:
			_wave_banner = ""
		queue_redraw()

func _draw() -> void:
	_draw_hand_strip_backdrop()
	_draw_wave_shout()

func _draw_hand_strip_backdrop() -> void:
	# Soft scrim across the bottom that the cards / val / ability rail sit
	# on. Anchors them visually so they don't float against the world floor.
	# A short vertical gradient at the top of the band fades from transparent
	# into the solid scrim — sells the depth without cutting hard from the
	# world. Stacked translucent rects rather than a Shader.
	var band_h: float = HAND_BAND_HEIGHT
	var band_top: float = size.y - band_h
	var solid_color: Color = DesignTokens.hand_backdrop_color()
	var fade_h := 64.0
	# Solid lower portion.
	draw_rect(Rect2(0.0, band_top + fade_h, size.x, band_h - fade_h), solid_color, true)
	# Top fade — N thin slices stepping from alpha 0 to solid alpha.
	var steps := 16
	var slice_h: float = fade_h / float(steps)
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var c := Color(solid_color.r, solid_color.g, solid_color.b, solid_color.a * t)
		draw_rect(Rect2(0.0, band_top + i * slice_h, size.x, slice_h + 1.0), c, true)
	# ─── Phase-clarity accent strip ──────────────────────────────────────
	# Thin colored line riding the top of the band, color-coded by phase so
	# the player can tell at a glance whether they're buying (prep), fighting
	# (wave), or in the moment-between-waves (debrief).
	var accent_h := 3.0
	var accent_color := _phase_accent_color()
	# Subtle outer glow — wider, lower-alpha rect under the line.
	var glow := Color(accent_color.r, accent_color.g, accent_color.b, accent_color.a * 0.35)
	draw_rect(Rect2(0.0, band_top - 2.0, size.x, 6.0), glow, true)
	draw_rect(Rect2(0.0, band_top, size.x, accent_h), accent_color, true)

func _phase_accent_color() -> Color:
	match _phase_label:
		"Prep":
			# Warm gold — "your turn to spend".
			var c := DesignTokens.GOLD_COIN
			return Color(c.r, c.g, c.b, 0.85)
		"Wave":
			# Hero core — "the line is hot".
			var c := DesignTokens.core_color(GameState.hero_id)
			return Color(c.r, c.g, c.b, 0.90)
		"Debrief":
			# Val cream — "catch your breath".
			var c := DesignTokens.VAL_CREAM
			return Color(c.r, c.g, c.b, 0.65)
		_:
			return Color(1, 1, 1, 0.20)

func _draw_wave_shout() -> void:
	if _wave_banner == "":
		return
	# Splash band sits above the hand strip; soft scrim under the text.
	var band_h := 80.0
	var band_y := size.y * 0.32
	var band_rect := Rect2(0.0, band_y, size.x, band_h)
	draw_rect(band_rect, DesignTokens.SCRIM_SOFT, true)
	var font := DesignTokens.font_display()
	var fs := DesignTokens.FS_2XL
	var tw: float = font.get_string_size(_wave_banner, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font,
		Vector2((size.x - tw) * 0.5, band_y + band_h * 0.5 + 12.0),
		_wave_banner, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, DesignTokens.FG_1)
