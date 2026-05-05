extends Control
##
## HUD adapter — top-of-screen Buffalo HP / Core HP / coin / phase / round /
## wave timer. Phase 1 ships the canonical readouts only; the polished
## hi-fi v3 layout (hero badge, val strip, ability rail, etc.) lives in
## godot-prototype and is out of scope until the architecture pivot lands.
##
## Reads from GameState directly + listens to logic-module signals via the
## `bind` API. No tile-coord knowledge — purely numeric / phase rendering.

const Sectors := preload("res://data/sectors.gd")

var _economy
var _wave_director
var _sector
var _prep_seconds_left: float = 0.0
var _coin_balance: int = 0
var _round_index: int = 1
var _phase: String = "prep"
var _banner_text: String = ""
var _banner_until: float = 0.0

func bind(economy, wave_director, sector) -> void:
	_economy = economy
	_wave_director = wave_director
	_sector = sector
	_economy.balance_changed.connect(_on_balance_changed)
	_coin_balance = _economy.balance
	_wave_director.prep_timer_changed.connect(_on_prep_timer)
	_wave_director.round_started.connect(_on_round_started)
	_wave_director.wave_started.connect(_on_wave_started)
	_wave_director.wave_ended.connect(_on_wave_ended)
	_sector.core_hp_changed.connect(_on_core_hp_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.hero_hp_changed.connect(_on_hero_hp_changed)

func _ready() -> void:
	# Top band reserve. The original's hi-fi HUD spans 144px tall; we keep
	# the same so card hand math stays consistent.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_top = 0.0
	offset_bottom = 144.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _process(_delta: float) -> void:
	# Cheap repaint each frame — cooldown fades and prep timer animate
	# without separate signals.
	queue_redraw()

func show_banner(text: String, duration_seconds: float) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + duration_seconds

func _on_balance_changed(new_balance: int) -> void:
	_coin_balance = new_balance

func _on_prep_timer(seconds_left: float) -> void:
	_prep_seconds_left = seconds_left

func _on_round_started(round_index: int) -> void:
	_round_index = round_index
	show_banner("Round %d — prep" % round_index, 2.0)

func _on_wave_started(round_index: int, composition: Dictionary) -> void:
	_round_index = round_index
	var label: String = composition.get("name", "")
	show_banner("Wave %d — %s" % [round_index, label], 2.5)

func _on_wave_ended(_round_idx: int, victory: bool) -> void:
	if victory:
		show_banner("Wave clear", 2.0)
	else:
		show_banner("The line broke.", 3.0)

func _on_phase_changed(phase: String) -> void:
	_phase = phase

func _on_hero_hp_changed(_current: float, _maximum: float) -> void:
	pass  # repaint covers it

func _on_core_hp_changed(_current: float, _maximum: float) -> void:
	pass

# ── Drawing ──────────────────────────────────────────────────────────────
func _draw() -> void:
	# Translucent band so the floor underneath still reads.
	var bg := Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.55)
	draw_rect(Rect2(0, 0, size.x, size.y), bg, true)
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), DesignTokens.DIVIDER, 2.0)
	# Pads around rendered chips.
	var pad: float = float(DesignTokens.SPACE_4)
	# Hero HP — left.
	_draw_label_chip(Vector2(pad, 16),
		"BUFFALO", "%d / %d" % [int(GameState.hero_hp), int(GameState.hero_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.hero_hp, GameState.hero_hp_max)),
	)
	# Core HP — left of center.
	_draw_label_chip(Vector2(pad + 220, 16),
		"CORE", "%d / %d" % [int(GameState.core_hp), int(GameState.core_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.core_hp, GameState.core_hp_max)),
	)
	# Coin balance — center.
	_draw_label_chip(Vector2(pad + 460, 16),
		"COIN", str(_coin_balance), DesignTokens.GOLD_COIN,
	)
	# Phase + round — right of coin.
	_draw_label_chip(Vector2(pad + 640, 16),
		"PHASE", "Round %d — %s" % [_round_index, _phase], DesignTokens.FG_2,
	)
	# Wave timer — only in prep.
	if _phase == "prep":
		_draw_label_chip(Vector2(pad + 940, 16),
			"PREP TIMER", _format_timer(_prep_seconds_left), DesignTokens.FG_2,
		)
	elif _phase == "wave":
		_draw_label_chip(Vector2(pad + 940, 16),
			"PHASE", "wave — hold the line", DesignTokens.HP_CRIT,
		)
	# Banner.
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _banner_text.is_empty() and now < _banner_until:
		_draw_banner(_banner_text)

func _draw_banner(text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = DesignTokens.FS_2XL
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = (size.x - w) * 0.5
	var y: float = 100.0
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignTokens.PARCHMENT_0)

func _draw_label_chip(pos: Vector2, label: String, value: String, value_color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_3)
	draw_string(font, pos + Vector2(0, 48), value, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, value_color)

func _hp_ratio(current: float, maximum: float) -> float:
	if maximum <= 0:
		return 0.0
	return clamp(current / maximum, 0.0, 1.0)

func _format_timer(seconds: float) -> String:
	# Voice rule: timers as `0:24`, never `24s`.
	var s: int = int(ceil(seconds))
	@warning_ignore("integer_division")
	var m: int = s / 60
	var r: int = s % 60
	return "%d:%02d" % [m, r]
