extends Control
##
## Top-of-screen HUD. Reads from GameState + bound logic modules. The
## values shown obey the voice rules:
##   - HP rendered as `124 / 160`
##   - Timer rendered as `0:24`
##   - Sentence case for labels, no emoji
##   - Hero name written in full

const Sectors := preload("res://data/sectors.gd")

var _coin: int = 0
var _round_index: int = 1
var _prep_seconds: float = 0.0
var _phase_label: String = "Prep"
var _wave_banner: String = ""
var _wave_banner_timeout: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.hero_hp_changed.connect(func(_a, _b): queue_redraw())
	GameState.phase_changed.connect(_on_phase_changed)
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
	# Wave-banner shouts are the one exemption from sentence case (per spec).
	_wave_banner = "WAVE %d — HOLD THE LINE" % round_index
	_wave_banner_timeout = 2.4
	queue_redraw()

func _on_wave_ended(_idx: int, victory: bool) -> void:
	# Param prefixed with `_` would normally signal "unused", but a leading-
	# underscore name still shadows the class member `_round_index` under 4.6.
	_wave_banner = "We held." if victory else "The line broke."
	_wave_banner_timeout = 3.0
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	# HUD strip background (top 64px).
	var strip := Rect2(0, 0, size.x, 64)
	draw_rect(strip, Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.78), true)
	draw_line(Vector2(0, 64), Vector2(size.x, 64), DesignTokens.DIVIDER, 2.0)
	# Hero — Buffalo HP.
	var hp := GameState.hero_hp
	var hp_max := GameState.hero_hp_max
	_draw_label("Buffalo", Vector2(24, 16), DesignTokens.FG_3, DesignTokens.FS_XS)
	_draw_label("%d / %d" % [int(hp), int(hp_max)], Vector2(24, 36), DesignTokens.FG_1, DesignTokens.FS_LG, true)
	var hp_ratio: float = 0.0 if hp_max == 0.0 else hp / hp_max
	draw_rect(Rect2(110, 44, 160, 6), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(110, 44, 160 * hp_ratio, 6), DesignTokens.hp_color(hp_ratio), true)
	# Core HP — middle-left.
	_draw_label("Core", Vector2(296, 16), DesignTokens.FG_3, DesignTokens.FS_XS)
	_draw_label("%d / %d" % [int(GameState.core_hp), int(GameState.core_hp_max)],
		Vector2(296, 36), DesignTokens.FG_1, DesignTokens.FS_LG, true)
	var core_ratio: float = 0.0 if GameState.core_hp_max == 0 else GameState.core_hp / GameState.core_hp_max
	draw_rect(Rect2(370, 44, 160, 6), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(370, 44, 160 * core_ratio, 6), DesignTokens.hp_color(core_ratio), true)
	# Coin — center.
	var coin_text := "%d coin" % _coin
	_draw_label("Balance", Vector2(560, 16), DesignTokens.FG_3, DesignTokens.FS_XS)
	_draw_label(coin_text, Vector2(560, 36), DesignTokens.GOLD_COIN, DesignTokens.FS_LG, true)
	# Phase + round — right.
	var phase_text := "%s — round %d" % [_phase_label, _round_index]
	_draw_label("Phase", Vector2(size.x - 280, 16), DesignTokens.FG_3, DesignTokens.FS_XS)
	_draw_label(phase_text, Vector2(size.x - 280, 36), DesignTokens.FG_1, DesignTokens.FS_LG, true)
	# Timer — far right.
	_draw_label("Timer", Vector2(size.x - 110, 16), DesignTokens.FG_3, DesignTokens.FS_XS)
	_draw_label(_format_timer(_prep_seconds), Vector2(size.x - 110, 36), DesignTokens.FG_1, DesignTokens.FS_LG, true)
	# Ready hint during prep.
	if _phase_label == "Prep":
		_draw_label("Press space to ready up", Vector2(size.x * 0.5 - 110, 70), DesignTokens.FG_3, DesignTokens.FS_SM, false)
	# Wave banner overlay.
	if _wave_banner != "":
		var banner_y := 200.0
		var banner_h := 72.0
		var banner_rect := Rect2(0, banner_y, size.x, banner_h)
		draw_rect(banner_rect, Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.7), true)
		var text_w := font.get_string_size(_wave_banner, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_2XL).x
		draw_string(font, Vector2((size.x - text_w) * 0.5, banner_y + banner_h * 0.5 + 12),
			_wave_banner, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_2XL, DesignTokens.FG_1)

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int, _tabular: bool = false) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _format_timer(seconds: float) -> String:
	var s: int = int(ceil(seconds))
	@warning_ignore("integer_division")
	var minutes: int = s / 60
	var rem: int = s % 60
	return "%d:%02d" % [minutes, rem]
