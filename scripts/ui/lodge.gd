extends Control
##
## The Lodge — warm shared hub between runs. The player lands here on boot
## and after each run completes (BUF-112). Three stations: pick a hero,
## unlock cards (stub in v1), start a run. Val sleeps by the fire. The
## trophy wall is empty for now — run history will populate it later.
##
## All visuals come from `DesignTokens` and the `data/heroes.gd` table.
## Drawn via `_draw()` in the same idiom as hero_select / end_screen so the
## three overlays keep one consistent rendering pattern.

const Heroes := preload("res://data/heroes.gd")

signal pick_hero_requested()
signal start_run_requested()
signal unlock_cards_requested()

# ─── Layout (tuned against 1280×720 viewport) ─────────────────────────────
const STATION_SIZE := Vector2(280, 220)
const STATION_GAP := 32.0
const STATIONS_TOP_Y := 226.0
const HEADER_TOP_Y := 48.0
const TROPHY_FRAME_SIZE := Vector2(56, 76)
const TROPHY_FRAMES := 5
const TROPHY_GAP := 10.0
const TROPHY_RIGHT_MARGIN := 56.0
const TROPHY_BOTTOM_Y := 612.0
const VAL_SCALE := Vector2(0.7, 0.7)
const VAL_FOOTPRINT_OFFSET := Vector2(0, 8)
const VAL_LEFT_MARGIN := 56.0

const STATION_PICK := "pick"
const STATION_UNLOCKS := "unlocks"
const STATION_START := "start"
const STATION_ORDER := [STATION_PICK, STATION_UNLOCKS, STATION_START]

# ─── Inside-joke flavor (warm, not ironic) ────────────────────────────────
# These are the small lines that make the Lodge feel like a place. Per
# README voice rules: sentence case, no emoji, em dashes are fine.
const HEADER_EYEBROW := "THE LODGE"
const HEADER_HEADLINE := "Between runs."
const HEADER_SUB := "Warm fire. Cold outside. We pick our post when we're ready."
const TROPHY_CAPTION := "Trophy wall — fills as we go."
const VAL_LINE := "Val · sleeping by the fire (the watch is long)."

var _hover_station: String = ""
var _val_texture: Texture2D = null
# Toast surfaced on the unlocks station for v1. A line of warm flavor that
# fades after a few seconds, so the click reads as deliberate rather than
# broken. Length tracked separately from the static draw.
var _toast_text: String = ""
var _toast_remaining: float = 0.0
const TOAST_DURATION := 3.6

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_val_texture = load("res://assets/totems/val.svg")
	set_process(false)

func open() -> void:
	visible = true
	_hover_station = ""
	_toast_text = ""
	_toast_remaining = 0.0
	move_to_front()
	queue_redraw()
	set_process(false)

func close() -> void:
	visible = false
	_hover_station = ""
	set_process(false)

func _process(delta: float) -> void:
	if _toast_remaining <= 0.0:
		set_process(false)
		return
	_toast_remaining = max(0.0, _toast_remaining - delta)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prior := _hover_station
		_hover_station = _station_at(event.position)
		if prior != _hover_station:
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sid := _station_at(event.position)
		match sid:
			STATION_PICK:
				pick_hero_requested.emit()
			STATION_START:
				start_run_requested.emit()
			STATION_UNLOCKS:
				_show_toast("The cards you have are the cards you have — for now.")
				unlock_cards_requested.emit()

func _show_toast(msg: String) -> void:
	_toast_text = msg
	_toast_remaining = TOAST_DURATION
	set_process(true)
	queue_redraw()

func _station_at(local_pos: Vector2) -> String:
	for i in STATION_ORDER.size():
		if _station_rect(i).has_point(local_pos):
			return STATION_ORDER[i]
	return ""

func _station_rect(index: int) -> Rect2:
	var total_w := float(STATION_ORDER.size()) * STATION_SIZE.x \
		+ float(STATION_ORDER.size() - 1) * STATION_GAP
	var start_x := (size.x - total_w) * 0.5
	var x := start_x + float(index) * (STATION_SIZE.x + STATION_GAP)
	return Rect2(Vector2(x, STATIONS_TOP_Y), STATION_SIZE)

func _draw() -> void:
	_draw_background()
	_draw_lantern_strip()
	_draw_header()
	_draw_trophy_wall()
	for i in STATION_ORDER.size():
		_draw_station(i, STATION_ORDER[i])
	_draw_val()
	if _toast_remaining > 0.0:
		_draw_toast()

func _draw_background() -> void:
	# Night-0 ground per design system. No gradient across the whole screen
	# (gradients are reserved for hero-totem inner glow on cards). The fire
	# glow at the bottom is the warm accent that lets the room read as lit.
	draw_rect(Rect2(Vector2.ZERO, size), DesignTokens.NIGHT_0, true)
	# Soft vignette: a single dimmer band at the very top + bottom so the
	# eye settles toward the stations in the middle. Two thin strips, not
	# a radial — radial gradients are also off-limits per the design rules.
	var vignette_h := 96.0
	for i in range(int(vignette_h)):
		var t := 1.0 - float(i) / vignette_h
		var a := 0.32 * t
		draw_rect(Rect2(Vector2(0, i), Vector2(size.x, 1)),
			Color(0.0, 0.0, 0.0, a), true)
		draw_rect(Rect2(Vector2(0, size.y - i - 1), Vector2(size.x, 1)),
			Color(0.0, 0.0, 0.0, a * 0.7), true)

func _draw_lantern_strip() -> void:
	# Three faction lanterns down the left margin. The room belongs to all
	# three heroes, so the wayfinding hint runs along the wall as soft
	# glows the player can't miss but doesn't have to "use".
	var x := 22.0
	var y := 168.0
	var w := 6.0
	var h := 64.0
	var gap := 16.0
	var factions := ["Goose", "Buffalo", "Fox"]
	for i in factions.size():
		var rect := Rect2(Vector2(x, y + float(i) * (h + gap)), Vector2(w, h))
		draw_rect(rect, DesignTokens.lantern_color(factions[i]), true)
		draw_rect(rect, DesignTokens.core_color(factions[i]), false, 1.0)

func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	var center_x := size.x * 0.5
	var eyebrow_w := font.get_string_size(HEADER_EYEBROW, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS).x
	draw_string(font, Vector2(center_x - eyebrow_w * 0.5, HEADER_TOP_Y),
		HEADER_EYEBROW, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	var headline_w := font.get_string_size(HEADER_HEADLINE, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL).x
	draw_string(font, Vector2(center_x - headline_w * 0.5, HEADER_TOP_Y + 56),
		HEADER_HEADLINE, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL, DesignTokens.FG_1)
	var sub_w := font.get_string_size(HEADER_SUB, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
	draw_string(font, Vector2(center_x - sub_w * 0.5, HEADER_TOP_Y + 92),
		HEADER_SUB, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, DesignTokens.FG_2)

func _draw_trophy_wall() -> void:
	# Anchored bottom-right so the room composition reads: Val by the
	# fire on the left, trophy wall on the right, the stations the spine
	# down the middle. Frames are stubs in v1 — populated by run history
	# in M2.
	var font := ThemeDB.fallback_font
	var total_w := float(TROPHY_FRAMES) * TROPHY_FRAME_SIZE.x \
		+ float(TROPHY_FRAMES - 1) * TROPHY_GAP
	var x0 := size.x - TROPHY_RIGHT_MARGIN - total_w
	var top_y := TROPHY_BOTTOM_Y - TROPHY_FRAME_SIZE.y
	draw_string(font, Vector2(x0, top_y - 14),
		TROPHY_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	for i in TROPHY_FRAMES:
		var rect := Rect2(Vector2(x0 + float(i) * (TROPHY_FRAME_SIZE.x + TROPHY_GAP), top_y),
			TROPHY_FRAME_SIZE)
		draw_rect(rect, DesignTokens.NIGHT_1, true)
		draw_rect(rect, DesignTokens.DIVIDER, false, 1.0)
	# Tiny inside hint — empties read as deliberate, not unfinished.
	var hint := "(empty for now)"
	draw_string(font, Vector2(x0 + total_w - 100.0, TROPHY_BOTTOM_Y + 18),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)

func _draw_station(index: int, station_id: String) -> void:
	var rect := _station_rect(index)
	var is_hover := _hover_station == station_id
	var spec := _station_spec(station_id)
	var accent: Color = spec["accent"]
	# Card body — Night-1 (system bg-card token) so the parchment-colored
	# CTA strip below pops against it. Hover lightens to Night-2 per the
	# design system's hover rule.
	var body_color := DesignTokens.NIGHT_2 if is_hover else DesignTokens.NIGHT_1
	draw_rect(rect, body_color, true)
	# Hero-tinted top lantern strip — the cozy signature from the design
	# system. Full strength on hover, low alpha at rest.
	var lantern_h := 8.0
	var lantern_alpha: float = 0.85 if is_hover else 0.45
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, lantern_h)),
		Color(accent.r, accent.g, accent.b, lantern_alpha), true)
	# Hairline border with hover lift in the accent color.
	var border_w := 2.0 if is_hover else 1.0
	var border_color := accent if is_hover else DesignTokens.DIVIDER
	draw_rect(rect, border_color, false, border_w)
	# Title + flavor.
	var font := ThemeDB.fallback_font
	var pad := float(DesignTokens.SPACE_4)
	var title: String = spec["title"]
	var subtitle: String = spec["subtitle"]
	var flavor: String = spec["flavor"]
	draw_string(font, rect.position + Vector2(pad, 36 + lantern_h),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_2XL, DesignTokens.FG_1)
	if subtitle != "":
		draw_string(font, rect.position + Vector2(pad, 60 + lantern_h),
			subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_3)
	# Flavor wraps to two lines — same multiline trick as hero_select.
	draw_multiline_string(font, rect.position + Vector2(pad, 100 + lantern_h),
		flavor, HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - pad * 2.0, DesignTokens.FS_SM, 3, DesignTokens.FG_2)
	# CTA strip at the bottom — primary uses accent fill, secondary stays
	# Night-2. Voice rules: sentence case.
	var cta_h := 36.0
	var cta_rect := Rect2(rect.position + Vector2(0, rect.size.y - cta_h),
		Vector2(rect.size.x, cta_h))
	var is_primary: bool = spec.get("primary", false)
	var cta_bg: Color = accent if is_primary else DesignTokens.NIGHT_3
	if is_hover and not is_primary:
		# Lift secondary CTAs on hover so the click target reads warmer.
		cta_bg = Color(accent.r, accent.g, accent.b, 0.25)
	draw_rect(cta_rect, cta_bg, true)
	var cta: String = spec["cta"]
	var cta_color: Color = spec.get("cta_color", DesignTokens.FG_1)
	var cta_w := font.get_string_size(cta, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
	draw_string(font, cta_rect.position + Vector2((cta_rect.size.x - cta_w) * 0.5, 24),
		cta, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, cta_color)

func _station_spec(station_id: String) -> Dictionary:
	# Built per-frame because the Start station's subtitle changes with the
	# currently selected hero. Tiny dict — the cost is fine.
	match station_id:
		STATION_PICK:
			var current := _current_hero_name()
			return {
				"title": "Pick your hero",
				"subtitle": "Currently: %s" % current,
				"flavor": "Three posts. Goose, Buffalo, Fox. Pick where you stand tonight.",
				"cta": "Choose a hero",
				"accent": DesignTokens.core_color(GameState.hero_id),
				"cta_color": DesignTokens.ink_color(GameState.hero_id),
				"primary": false,
			}
		STATION_UNLOCKS:
			return {
				"title": "Card unlocks",
				"subtitle": "Locked — for now",
				"flavor": "Trophies the wall doesn't have yet. Come back when we've earned them.",
				"cta": "Open the chest",
				"accent": DesignTokens.PARCHMENT_3,
				"cta_color": DesignTokens.PARCHMENT_INK,
				"primary": false,
			}
		STATION_START:
			var hero_id := GameState.hero_id
			var hero_name := _current_hero_name()
			return {
				"title": "Start a run",
				"subtitle": "Running with %s" % hero_name,
				"flavor": "Lights down, line up. The wave's not going to hold itself.",
				"cta": "Out into the dark",
				"accent": DesignTokens.core_color(hero_id),
				"cta_color": DesignTokens.ink_color(hero_id),
				"primary": true,
			}
		_:
			return {
				"title": "—",
				"subtitle": "",
				"flavor": "",
				"cta": "",
				"accent": DesignTokens.FG_3,
				"cta_color": DesignTokens.FG_1,
				"primary": false,
			}

func _current_hero_name() -> String:
	# GameState defaults to "Buffalo" before the player has picked, so this
	# always resolves to one of the canonical names. Hero names are written
	# in full per the voice rules.
	var hid := GameState.hero_id
	if Heroes.ALL.has(hid):
		return Heroes.ALL[hid].name
	return "Buffalo"

func _draw_val() -> void:
	# Val sleeps by the fire — bottom-left of the room, mirror to the
	# trophy wall on the right. The fire is a warm orange glow rather
	# than a sprite (no fire art in v1); the heat reads as the small
	# ellipse beneath him. He's static for v1 — animated polish is M3.
	var fire_center := Vector2(VAL_LEFT_MARGIN + 60.0, size.y - 96.0)
	_draw_fire(fire_center)
	if _val_texture != null:
		var tex_size := _val_texture.get_size() * VAL_SCALE
		# Place Val's body to the right of the fire so the silhouette reads
		# as "curled up against the warmth", not "standing in the embers".
		var tex_pos := Vector2(fire_center.x + 48.0, fire_center.y - tex_size.y * 0.5)
		draw_texture_rect(_val_texture, Rect2(tex_pos + VAL_FOOTPRINT_OFFSET, tex_size), false)
	var font := ThemeDB.fallback_font
	# Caption tucked just below the fire — quiet, second-person warm.
	var caption_pos := Vector2(VAL_LEFT_MARGIN, size.y - 28.0)
	draw_string(font, caption_pos, VAL_LINE,
		HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_2)

func _draw_fire(center: Vector2) -> void:
	# Layered ellipses: a wide soft glow, a tighter ember, a hottest core.
	# All in faction-warm orange so the warmth reads as part of the
	# totem-warm palette rather than a stray decoration.
	var outer := DesignTokens.FOX_LANTERN
	var mid := Color(DesignTokens.FOX_CORE.r, DesignTokens.FOX_CORE.g,
		DesignTokens.FOX_CORE.b, 0.45)
	var hot := Color(DesignTokens.GOOSE_CORE.r, DesignTokens.GOOSE_CORE.g,
		DesignTokens.GOOSE_CORE.b, 0.85)
	_draw_ellipse(center, Vector2(112.0, 36.0), outer)
	_draw_ellipse(center, Vector2(72.0, 22.0), mid)
	_draw_ellipse(center + Vector2(0, -2), Vector2(28.0, 10.0), hot)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	const SEGMENTS := 24
	var pts := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func _draw_toast() -> void:
	# Anchored just above the station row so the click→message connection
	# is obvious without a full-screen modal.
	var font := ThemeDB.fallback_font
	var fade: float = clamp(_toast_remaining / TOAST_DURATION, 0.0, 1.0)
	# Ease the last quarter of the toast into a fade so it doesn't blink off.
	var alpha: float = 1.0 if fade > 0.25 else fade / 0.25
	var pad := Vector2(18.0, 10.0)
	var text_w := font.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM).x
	var rect_size := Vector2(text_w + pad.x * 2.0, DesignTokens.FS_SM + pad.y * 2.0)
	var rect_pos := Vector2((size.x - rect_size.x) * 0.5, STATIONS_TOP_Y - rect_size.y - 14.0)
	var bg := DesignTokens.NIGHT_1
	bg.a = 0.92 * alpha
	draw_rect(Rect2(rect_pos, rect_size), bg, true)
	var border := DesignTokens.PARCHMENT_3
	border.a = alpha * 0.6
	draw_rect(Rect2(rect_pos, rect_size), border, false, 1.0)
	var text_color := DesignTokens.FG_1
	text_color.a = alpha
	draw_string(font, rect_pos + Vector2(pad.x, pad.y + DesignTokens.FS_SM),
		_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, text_color)
