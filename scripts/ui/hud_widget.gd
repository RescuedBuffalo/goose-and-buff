extends Control
##
## HUD adapter — survival rebuild. Top-bar reads "Day N — gather and
## prepare" or "Day N — hold the line" with a phase countdown; left
## chips show Buffalo HP and lodge core HP. Inventory + equipped slot
## live in their own InventoryHud control along the bottom band — this
## widget covers the *top* of the viewport only.
##
## Card hand, deck/discard, prep/wave button, signature ability rail —
## all gone. Phase progresses automatically via DayNightCycle.

const DayNight := preload("res://data/day_night.gd")

var _day_index: int = 1
var _phase: int = DayNight.PHASE_DAY
var _phase_seconds: float = DayNight.DAY_SECONDS
var _banner_text: String = ""
var _banner_until: float = 0.0

func bind(day_night) -> void:
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.phase_timer_tick.connect(_on_phase_timer)
	GameState.hero_hp_changed.connect(func(_a, _b): queue_redraw())

func _ready() -> void:
	# Fixed band at the very top — 96 px tall is enough for two lines of
	# chips without crowding the world below.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_top = 0.0
	offset_bottom = 96.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func show_banner(text: String, duration_seconds: float) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + duration_seconds

func _on_phase_changed(phase: int, day_index: int) -> void:
	_phase = phase
	_day_index = day_index
	# Phase-change banners stay short and warm — sentence case, no shouts.
	match phase:
		DayNight.PHASE_DAY:
			show_banner("Day %d — gather and prepare." % day_index, 2.0)
		DayNight.PHASE_DUSK:
			show_banner("The light is going.", 2.0)
		DayNight.PHASE_NIGHT:
			show_banner("Night %d — hold the line." % day_index, 2.5)
		DayNight.PHASE_DAWN:
			show_banner("We held.", 2.0)

func _on_phase_timer(seconds_left: float, phase: int) -> void:
	_phase_seconds = seconds_left
	_phase = phase

# ── Drawing ──────────────────────────────────────────────────────────
func _draw() -> void:
	var bg := Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.62)
	draw_rect(Rect2(0, 0, size.x, size.y), bg, true)
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), DesignTokens.DIVIDER, 2.0)
	var pad: float = float(DesignTokens.SPACE_4)
	# Hero HP — left.
	_draw_label_chip(Vector2(pad, 14),
		"BUFFALO", "%d / %d" % [int(GameState.hero_hp), int(GameState.hero_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.hero_hp, GameState.hero_hp_max)),
	)
	# Lodge core HP — left of center.
	_draw_label_chip(Vector2(pad + 240, 14),
		"LODGE", "%d / %d" % [int(GameState.core_hp), int(GameState.core_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.core_hp, GameState.core_hp_max)),
	)
	# Phase headline — center. "Day 2 — gather and prepare" or "Night 2 — hold the line".
	var headline: String = _phase_headline()
	var font: Font = ThemeDB.fallback_font
	var headline_w: float = font.get_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG).x
	draw_string(font, Vector2((size.x - headline_w) * 0.5, 36), headline,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, DesignTokens.PARCHMENT_0)
	# Countdown timer — right of headline.
	var timer: String = _format_timer(_phase_seconds)
	var timer_w: float = font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG).x
	draw_string(font, Vector2(size.x - pad - timer_w, 36), timer,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, DesignTokens.FG_2)
	# Banner overlay below the band when fresh.
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _banner_text.is_empty() and now < _banner_until:
		_draw_banner(_banner_text)

func _phase_headline() -> String:
	match _phase:
		DayNight.PHASE_DAY: return "Day %d — gather and prepare" % _day_index
		DayNight.PHASE_DUSK: return "Day %d — dusk" % _day_index
		DayNight.PHASE_NIGHT: return "Night %d — hold the line" % _day_index
		DayNight.PHASE_DAWN: return "Day %d — dawn" % _day_index
		_: return "Day %d" % _day_index

func _draw_banner(text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = DesignTokens.FS_2XL
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = (size.x - w) * 0.5
	var y: float = 78.0
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignTokens.PARCHMENT_0)

func _draw_label_chip(pos: Vector2, label: String, value: String, value_color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, 14), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	draw_string(font, pos + Vector2(0, 42), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, value_color)

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
