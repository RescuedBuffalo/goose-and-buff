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
const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const Heroes := preload("res://data/heroes.gd")

var _day_index: int = 1
var _phase: int = DayNight.PHASE_DAY
var _phase_seconds: float = DayNight.DAY_SECONDS
var _banner_text: String = ""
var _banner_until: float = 0.0
# Cached rounded-up second of _phase_seconds — we redraw only when this
# rolls over (or when other state changes), instead of every frame. The
# timer string only changes at second boundaries, so per-frame redraws
# are wasted work.
var _last_drawn_timer_int: int = -1
var _banner_active: bool = false
# Connection-state banner (BUF-155). When a peer's state changes the
# HUD shows the seasonal-frame copy for ~3 seconds in the bottom band.
var _connection_banner: String = ""
var _connection_banner_until: float = 0.0
# Pulse phase for the in-combat portrait pulse (BUF-153). We don't run
# a tween — a simple sin(time) modulator is enough.
var _pulse_t: float = 0.0
# Cached reference to the main scene so we can read first-hit-peer +
# veil state for the teammate strip. main.gd has a getter for it.
var _main_ref: Node = null

func bind(day_night) -> void:
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.phase_timer_tick.connect(_on_phase_timer)
	GameState.hero_hp_changed.connect(func(_a, _b): queue_redraw())
	GameState.core_hp_changed.connect(func(_a, _b): queue_redraw())
	# Q ability cooldown rail (BUF-156). The signal fires on cast (max
	# stamped) and on every per-frame tick the router applies, so the
	# rail re-renders only when the cooldown actually moves.
	GameState.signature_cooldown_changed.connect(func(_a, _b): queue_redraw())
	# Connection-state banner copy fires off MpIo when a peer connects /
	# drops / reconnects. The autoload exists in solo too but never emits
	# unless a peer is bound, so this listener is safe to wire always.
	if not MpIo.peer_state_changed.is_connected(_on_peer_state_changed):
		MpIo.peer_state_changed.connect(_on_peer_state_changed)
	_main_ref = get_tree().current_scene

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

func _process(delta: float) -> void:
	# Redraw only when something visible has actually changed:
	#   - timer string crossed a second boundary
	#   - banner just expired (so we wipe the trailing text)
	# HP / phase changes piggy-back on signal-driven queue_redraws.
	var timer_int: int = int(ceil(_phase_seconds))
	var should_redraw: bool = false
	if timer_int != _last_drawn_timer_int:
		_last_drawn_timer_int = timer_int
		should_redraw = true
	var now: float = Time.get_ticks_msec() / 1000.0
	var banner_active_now: bool = not _banner_text.is_empty() and now < _banner_until
	if banner_active_now != _banner_active:
		_banner_active = banner_active_now
		should_redraw = true
	# In-combat portrait pulse — repaint every frame during a wave so
	# the sin() modulator animates. Cheap; only the teammate strip lives
	# in the redraw region.
	if MpIo.is_multiplayer():
		_pulse_t += delta
		should_redraw = true
	if should_redraw:
		queue_redraw()

func show_banner(text: String, duration_seconds: float) -> void:
	_banner_text = text
	_banner_until = Time.get_ticks_msec() / 1000.0 + duration_seconds
	_banner_active = true
	queue_redraw()

func _on_phase_changed(phase: int, day_index: int) -> void:
	_phase = phase
	_day_index = day_index
	queue_redraw()
	# Phase-change banners stay short and warm — sentence case, no shouts.
	# Seasonal-frame language (BUF-146): days carry a chapter name, not a
	# wave number. "First frost → the long cold → the deep dark → before
	# the thaw" is the locked vocabulary.
	#
	# The NIGHT case is intentionally absent: the wave-start path raises
	# its own ALL-CAPS archetype shout via show_banner (e.g. "NIGHT 3 —
	# A BIG ONE INCOMING"), and a duplicate sentence-case banner here
	# would just flicker underneath it.
	match phase:
		DayNight.PHASE_DAY:
			show_banner("%s — %s" % [_day_chapter_title(day_index), _day_chapter_action(day_index)], 2.4)
		DayNight.PHASE_DUSK:
			show_banner("The light is going.", 2.0)
		DayNight.PHASE_DAWN:
			show_banner(_dawn_banner_text(day_index), 2.0)

func _on_phase_timer(seconds_left: float, phase: int) -> void:
	_phase_seconds = seconds_left
	_phase = phase

# ── Drawing ──────────────────────────────────────────────────────────
func _draw() -> void:
	var bg := Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.62)
	draw_rect(Rect2(0, 0, size.x, size.y), bg, true)
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), DesignTokens.DIVIDER, 2.0)
	var pad: float = float(DesignTokens.SPACE_4)
	# Local hero HP — left chip carries the local hero's totem name.
	var local_hero_id: String = GameState.hero_id.to_upper() if not GameState.hero_id.is_empty() else "BUFFALO"
	_draw_label_chip(Vector2(pad, 14),
		local_hero_id, "%d / %d" % [int(GameState.hero_hp), int(GameState.hero_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.hero_hp, GameState.hero_hp_max)),
	)
	# Lodge core HP — left of center.
	_draw_label_chip(Vector2(pad + 240, 14),
		"LODGE", "%d / %d" % [int(GameState.core_hp), int(GameState.core_hp_max)],
		DesignTokens.hp_color(_hp_ratio(GameState.core_hp, GameState.core_hp_max)),
	)
	# Q signature ability cooldown rail (BUF-156). Sits between the lodge
	# chip and the centered headline. Sentence-case "Q — Charge" label;
	# the value reads "Ready" when off-cooldown and "0:04" while ticking
	# (voice rule — never "4s"). A thin rail under the chip fills back
	# toward the right as the cooldown drains so peripheral vision picks
	# up "almost ready" without re-reading the timer text.
	_draw_signature_cooldown_chip(Vector2(pad + 480, 14))
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
	# Multiplayer-only surface: teammate portrait strip + connection
	# banner. Hidden in solo so the M2 single-player look stays clean.
	if MpIo.is_multiplayer():
		_draw_teammate_strip(font)
	if not _connection_banner.is_empty() and now < _connection_banner_until:
		_draw_connection_banner(_connection_banner, font)

func _draw_teammate_strip(font: Font) -> void:
	# Three portraits along the right edge of the top band. Each cell
	# shows the totem name + a connection-state dot. The first-hit-hero
	# pulses (BUF-153 in-combat indicator). Veiled teammates show only
	# this pulse — the *what's coming* stays off-screen.
	var pad: float = float(DesignTokens.SPACE_4)
	var cell_w: float = 130.0
	var cell_h: float = 56.0
	var spacing: float = 8.0
	var first_hit: int = 0
	if _main_ref != null and _main_ref.has_method("wave_first_hit_peer"):
		first_hit = int(_main_ref.wave_first_hit_peer())
	var slot_index: int = 0
	for slot_pid in MpIo.lobby.snapshot():
		var pid: int = int(slot_pid.peer_id)
		if pid == 0:
			continue
		var hero_id: String = String(slot_pid.hero_id)
		var x: float = size.x - pad - (cell_w + spacing) * 3.0 + (cell_w + spacing) * float(slot_index)
		var y: float = 6.0
		var bg_color := Color(DesignTokens.NIGHT_2.r, DesignTokens.NIGHT_2.g, DesignTokens.NIGHT_2.b, 0.78)
		# In-combat pulse: highlight the first-hit-hero portrait while
		# the wave is active. sin() modulates the border alpha.
		var border := DesignTokens.DIVIDER
		var border_w: float = 2.0
		if pid == first_hit and _phase == DayNight.PHASE_NIGHT:
			var pulse: float = 0.5 + 0.5 * sin(_pulse_t * 6.0)
			border = DesignTokens.HP_CRIT
			border_w = 3.0 + pulse * 2.0
		draw_rect(Rect2(x, y, cell_w, cell_h), bg_color, true)
		draw_rect(Rect2(x, y, cell_w, cell_h), border, false, border_w)
		draw_string(font, Vector2(x + 8, y + 22), hero_id,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.PARCHMENT_0)
		# State dot — a small disc whose color reflects connection state.
		var state_id: String = String(MpIo.peer_states.get(pid, MultiplayerDataClass.STATE_CONNECTED))
		var dot_color: Color = _state_dot_color(state_id)
		draw_circle(Vector2(x + cell_w - 14, y + 14), 5.0, dot_color)
		# Local hero gets a parchment outline so each player can find
		# themselves in the strip without reading totem names.
		if pid == MpIo.local_peer_id:
			draw_rect(Rect2(x + 2, y + 2, cell_w - 4, cell_h - 4), DesignTokens.PARCHMENT_2, false, 1.5)
		slot_index += 1

func _state_dot_color(state_id: String) -> Color:
	match state_id:
		MultiplayerDataClass.STATE_CONNECTED, MultiplayerDataClass.STATE_RECONNECTED:
			return DesignTokens.HP_FULL
		MultiplayerDataClass.STATE_RECONNECTING, MultiplayerDataClass.STATE_CONNECTING:
			return DesignTokens.HP_WARN
		MultiplayerDataClass.STATE_DROPPED, MultiplayerDataClass.STATE_HOST_DROPPED:
			return DesignTokens.HP_CRIT
		_:
			return DesignTokens.FG_3

func _draw_connection_banner(text: String, font: Font) -> void:
	# Bottom-of-band centered banner. Smaller than the wave banner so
	# they read distinct from each other.
	var fs: int = DesignTokens.FS_MD
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = (size.x - w) * 0.5
	var y: float = size.y - 18.0
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignTokens.FG_2)

func _on_peer_state_changed(_peer_id: int, state_id: String, hero_id: String) -> void:
	# Render the seasonal-frame copy for this transition for ~3.5s.
	# The state ids the multiplayer adapter uses come from data/
	# multiplayer.gd — connection_copy() handles the voice mapping.
	var copy: String = MultiplayerDataClass.connection_copy(state_id, hero_id)
	if copy.is_empty():
		return
	_connection_banner = copy
	_connection_banner_until = Time.get_ticks_msec() / 1000.0 + 3.5
	queue_redraw()

func _phase_headline() -> String:
	# Seasonal-frame chapter names (BUF-146). "Day 1 — first frost,
	# gather and prepare" / "Night 2 — the long cold, hold the line"
	# / "Day 3 — the deep dark, gather and prepare". The chapter
	# carries the seasonal weight; the verb tells the player what to do.
	match _phase:
		DayNight.PHASE_DAY: return "%s — gather and prepare" % _day_chapter_title(_day_index)
		DayNight.PHASE_DUSK: return "%s — dusk" % _day_chapter_title(_day_index)
		DayNight.PHASE_NIGHT: return "%s — hold the line" % _night_chapter_title(_day_index)
		DayNight.PHASE_DAWN: return "%s — dawn" % _day_chapter_title(_day_index)
		_: return _day_chapter_title(_day_index)

func _day_chapter_title(day_index: int) -> String:
	match day_index:
		1: return "Day 1 — first frost"
		2: return "Day 2 — the long cold"
		3: return "Day 3 — the deep dark"
		_: return "Day %d" % day_index

func _night_chapter_title(day_index: int) -> String:
	match day_index:
		1: return "Night 1 — first frost"
		2: return "Night 2 — the long cold"
		3: return "Night 3 — the deep dark"
		_: return "Night %d" % day_index

func _day_chapter_action(day_index: int) -> String:
	# Action verb pairs the chapter with what to do during it.
	match day_index:
		1: return "gather and prepare"
		2: return "stockpile and brace"
		3: return "ready the last stand"
		_: return "gather and prepare"

func _dawn_banner_text(day_index: int) -> String:
	# Final dawn (after night 3) reads "before the thaw" — the chapter
	# the seasonal frame closes on. Earlier dawns simply note "we held".
	if day_index >= DayNight.MAX_NIGHTS:
		return "Before the thaw — we held."
	return "We held."

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

func _draw_signature_cooldown_chip(pos: Vector2) -> void:
	# Companion to _draw_label_chip with a progress rail underneath. The
	# label uses sentence case ("Q — Charge") so it reads as guidance, not
	# a stat. Em dash matches the chapter-title voice elsewhere on the
	# band. Hidden if no hero is set yet (run-start screen path).
	var hero_id: String = GameState.hero_id
	if hero_id.is_empty():
		return
	var data: Dictionary = Heroes.ALL.get(hero_id, Heroes.Buffalo)
	# signatureAbility is the display name ("Buffalo charge" / "Dive" /
	# "Snatch"). Buffalo's variant is verbose; trim the totem prefix so
	# the chip reads parallel across heroes.
	var ability_name: String = String(data.get("signatureAbility", "Charge"))
	if ability_name.begins_with("Buffalo "):
		ability_name = ability_name.substr(8).capitalize()
	var label: String = "Q — %s" % ability_name
	var value: String
	var value_color: Color
	if GameState.signature_cooldown <= 0.0:
		value = "Ready"
		value_color = DesignTokens.PARCHMENT_0
	else:
		value = _format_timer(GameState.signature_cooldown)
		value_color = DesignTokens.FG_3
	var font: Font = ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, 14), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	draw_string(font, pos + Vector2(0, 42), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, value_color)
	# Progress rail. Fills left→right as the cooldown drains so the
	# rail is full at the moment the chip flips to "Ready".
	var rail_w: float = 160.0
	var rail_h: float = 4.0
	var rail_x: float = pos.x
	var rail_y: float = pos.y + 56.0
	draw_rect(Rect2(rail_x, rail_y, rail_w, rail_h), DesignTokens.NIGHT_2, true)
	if GameState.signature_cooldown_max > 0.0 and GameState.signature_cooldown > 0.0:
		var fill_ratio: float = clamp(1.0 - GameState.signature_cooldown / GameState.signature_cooldown_max, 0.0, 1.0)
		draw_rect(Rect2(rail_x, rail_y, rail_w * fill_ratio, rail_h), DesignTokens.PARCHMENT_2, true)
	else:
		draw_rect(Rect2(rail_x, rail_y, rail_w, rail_h), DesignTokens.PARCHMENT_0, true)

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
