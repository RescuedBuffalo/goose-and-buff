extends Node
##
## Canonical design tokens.
##
## RGB values mirror colors_and_type.css from the Buffalo & Goose design
## system, which itself derives from src/shared/Data/Sectors.lua. If a value
## here drifts from the CSS, the CSS wins — update here and re-source.
##
## Do not hardcode a Color or font size anywhere else in the project.

# ─── Hero totems ──────────────────────────────────────────────────────────
const GOOSE_FLOOR := Color8(255, 248, 190)
const GOOSE_CORE := Color8(252, 222, 40)
const GOOSE_INK := Color8(120, 88, 12)

const BUFFALO_FLOOR := Color8(150, 100, 70)
const BUFFALO_CORE := Color8(110, 70, 40)
const BUFFALO_INK := Color8(245, 230, 210)

const FOX_FLOOR := Color8(255, 185, 100)
const FOX_CORE := Color8(248, 130, 30)
const FOX_INK := Color8(60, 20, 5)

const VAL_MERLE := Color8(94, 110, 130)
const VAL_CREAM := Color8(238, 226, 200)
const VAL_RUST := Color8(170, 92, 56)

# ─── Neutrals ─────────────────────────────────────────────────────────────
const NIGHT_0 := Color8(18, 17, 22)
const NIGHT_1 := Color8(28, 26, 33)
const NIGHT_2 := Color8(40, 37, 47)
const NIGHT_3 := Color8(58, 53, 66)
const NIGHT_4 := Color8(82, 75, 92)
const DIVIDER := Color8(60, 60, 60)

const PARCHMENT_0 := Color8(252, 244, 226)
const PARCHMENT_1 := Color8(245, 232, 208)
const PARCHMENT_2 := Color8(232, 215, 184)
const PARCHMENT_INK := Color8(46, 32, 22)

# ─── Semantic ─────────────────────────────────────────────────────────────
const HP_FULL := Color8(122, 178, 96)
const HP_WARN := Color8(232, 180, 70)
const HP_CRIT := Color8(206, 76, 64)
const CORE_SHIELD := Color8(120, 195, 220)
const CORE_DOWN := Color8(120, 50, 50)
const XP_GLOW := Color8(196, 170, 255)
const GOLD_COIN := Color8(244, 196, 84)

const FG_1 := PARCHMENT_0
const FG_2 := Color8(214, 204, 188)
const FG_3 := Color8(160, 150, 138)

# ─── Hi-Fi v3 additions (signoff: game1/hifi-v3-signoff.md) ──────────────
# Alpha-bearing values are stored as Color(r, g, b, a) so consumers can pass
# them straight to draw_rect without recomposing.
const SCRIM_DEEP := Color(8.0 / 255.0, 7.0 / 255.0, 11.0 / 255.0, 0.72)
const SCRIM_SOFT := Color(8.0 / 255.0, 7.0 / 255.0, 11.0 / 255.0, 0.32)
const HELP_LINE := Color8(206, 76, 64)
const HELP_FILL := Color(206.0 / 255.0, 76.0 / 255.0, 64.0 / 255.0, 0.14)
const HELP_INK := Color8(252, 226, 222)
const GOOSE_LANTERN := Color(252.0 / 255.0, 222.0 / 255.0, 40.0 / 255.0, 0.14)
const BUFFALO_LANTERN := Color(170.0 / 255.0, 110.0 / 255.0, 70.0 / 255.0, 0.14)
const FOX_LANTERN := Color(248.0 / 255.0, 130.0 / 255.0, 30.0 / 255.0, 0.16)
const CORE_FELL_BG := Color8(60, 22, 18)
const CORE_FELL_LINE := Color8(180, 70, 60)
const PARCHMENT_3 := Color8(218, 198, 162)
const PIP_COMBAT_BG := Color8(206, 76, 64)
const PIP_COMBAT_FG := Color8(252, 244, 226)

# ─── Type sizes (Roblox UI floor: 14px @ 1080p) ───────────────────────────
const FS_XS := 12
const FS_SM := 14
const FS_MD := 16
const FS_LG := 20
const FS_XL := 26
const FS_2XL := 34
const FS_3XL := 46
const FS_4XL := 64
const FS_DISPLAY := 88

# ─── Spacing — multiples of 4 ─────────────────────────────────────────────
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const SPACE_6 := 32
const SPACE_7 := 48

# ─── Radii ────────────────────────────────────────────────────────────────
const RADIUS_2 := 8
const RADIUS_3 := 14
const RADIUS_4 := 22

# ─── Totem textures ───────────────────────────────────────────────────────
# Same source files used by hero.gd / hero_select.gd — preloaded once here so
# every UI surface that wants the artwork (badge, val strip, ability rail,
# cards, debrief …) shares one cached Texture2D and stays consistent with the
# in-world hero sprite.
const TOTEM_BUFFALO := preload("res://assets/totems/buffalo.png")
const TOTEM_GOOSE := preload("res://assets/totems/goose.svg")
const TOTEM_FOX := preload("res://assets/totems/fox.svg")
const TOTEM_VAL := preload("res://assets/totems/val.svg")

# ─── Hero look-up by faction id ───────────────────────────────────────────
func floor_color(faction: String) -> Color:
	match faction:
		"Goose": return GOOSE_FLOOR
		"Buffalo": return BUFFALO_FLOOR
		"Fox": return FOX_FLOOR
		_: return NIGHT_2

func core_color(faction: String) -> Color:
	match faction:
		"Goose": return GOOSE_CORE
		"Buffalo": return BUFFALO_CORE
		"Fox": return FOX_CORE
		_: return NIGHT_3

func ink_color(faction: String) -> Color:
	match faction:
		"Goose": return GOOSE_INK
		"Buffalo": return BUFFALO_INK
		"Fox": return FOX_INK
		_: return FG_1

func hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return HP_FULL
	if ratio > 0.25:
		return HP_WARN
	return HP_CRIT

func lantern_color(faction: String) -> Color:
	# Hi-fi v3 HeroBadge lantern strip — soft tinted glow on the totem side
	# of the badge. Faction-keyed alpha-bearing variant.
	match faction:
		"Goose": return GOOSE_LANTERN
		"Buffalo": return BUFFALO_LANTERN
		"Fox": return FOX_LANTERN
		_: return Color(NIGHT_3.r, NIGHT_3.g, NIGHT_3.b, 0.14)

func hero_core_border(faction: String) -> Color:
	# WavePill border rule (hi-fi v3): always 1px hero-core at 0.45 alpha;
	# only fill / glow / pulse vary across variants.
	var c := core_color(faction)
	return Color(c.r, c.g, c.b, 0.45)

func totem_texture(faction: String) -> Texture2D:
	match faction:
		"Goose": return TOTEM_GOOSE
		"Buffalo": return TOTEM_BUFFALO
		"Fox": return TOTEM_FOX
		"Val": return TOTEM_VAL
		_: return null

# ─── Fonts ────────────────────────────────────────────────────────────────
# Loaded lazily so the autoload doesn't crash on first import (the .ttf files
# are added in a separate step). Until they exist on disk, every accessor
# falls back to ThemeDB.fallback_font and the HUD still renders.
var _font_display: Font = null
var _font_body: Font = null
var _font_body_bold: Font = null
var _font_body_x_bold: Font = null
var _font_mono: Font = null
var _font_mono_bold: Font = null

func _try_load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res is Font:
		return res
	return null

func font_display() -> Font:
	# Young Serif — display headings (h-display, h1, h2, .ws-shout).
	if _font_display == null:
		_font_display = _try_load_font("res://assets/fonts/YoungSerif-Regular.ttf")
	return _font_display if _font_display != null else ThemeDB.fallback_font

func font_body() -> Font:
	# Nunito (variable wght). One .ttf file; weight is dialed in by the
	# `*_bold` accessors via FontVariation.
	if _font_body == null:
		_font_body = _try_load_font("res://assets/fonts/Nunito-VariableWght.ttf")
	return _font_body if _font_body != null else ThemeDB.fallback_font

func _nunito_at_weight(weight: int) -> Font:
	var base := font_body()
	if base == ThemeDB.fallback_font:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	return fv

func font_body_bold() -> Font:
	# Nunito @ wght 700 — names, eyebrow, hp numbers.
	if _font_body_bold == null:
		_font_body_bold = _nunito_at_weight(700)
	return _font_body_bold

func font_body_x_bold() -> Font:
	# Nunito @ wght 800 — combat pip, hb-name. Maps to font-weight 800
	# in the design CSS.
	if _font_body_x_bold == null:
		_font_body_x_bold = _nunito_at_weight(800)
	return _font_body_x_bold

func font_mono() -> Font:
	# JetBrains Mono — tabular numerics (HP counts, timers, balance).
	if _font_mono == null:
		_font_mono = _try_load_font("res://assets/fonts/JetBrainsMono-Regular.ttf")
	return _font_mono if _font_mono != null else ThemeDB.fallback_font

func font_mono_bold() -> Font:
	if _font_mono_bold == null:
		_font_mono_bold = _try_load_font("res://assets/fonts/JetBrainsMono-Bold.ttf")
	return _font_mono_bold if _font_mono_bold != null else font_mono()

# ─── Stylebox factories ──────────────────────────────────────────────────
# These mirror the named CSS classes in design/src/components.css so the
# Godot Control hierarchy can reuse the design language without re-deriving
# colors/radii/borders at every call site. Returns a fresh StyleBoxFlat each
# time — callers can mutate (e.g. swap the border color per hero) without
# poisoning shared state.

# Generic, used as a fallback / by `card_widget.gd`.
func panel_box(fill: Color, radius: int = RADIUS_3,
		border_color: Color = Color(0.0, 0.0, 0.0, 0.0),
		border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	if border_width > 0 and border_color.a > 0.0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	# Soft default warm-tinted shadow — matches `--shadow-1` from tokens.css.
	sb.shadow_color = Color(0.08, 0.04, 0.0, 0.32)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	return sb

# `.hero-badge`, `.wave-comp-panel`, `.help-banner`, `.help-toast`, `.val-strip`,
# `.ability-rail` — all share `border-radius: var(--radius-3)` and a hairline.
func card_panel_box(border_color: Color = Color(0.0, 0.0, 0.0, 0.0),
		border_width: int = 0) -> StyleBoxFlat:
	var sb := panel_box(
		Color(NIGHT_1.r, NIGHT_1.g, NIGHT_1.b, 0.92),
		RADIUS_3, border_color, border_width,
	)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

# `.wave-pill` — fully rounded "pill" body with a wider min-width and a
# stronger drop shadow. Caller sets the actual content margins.
func pill_panel_box() -> StyleBoxFlat:
	var sb := panel_box(
		Color(NIGHT_1.r, NIGHT_1.g, NIGHT_1.b, 0.92),
		999,
		Color(1.0, 1.0, 1.0, 0.06),
		1,
	)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 22
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

# `.ab-slot` — small rounded square for Q/E/F/R, lower contrast.
func slot_panel_box() -> StyleBoxFlat:
	return panel_box(NIGHT_2, RADIUS_2, Color(1.0, 1.0, 1.0, 0.06), 1)

# `.kbd`, `.ab-key` — tiny chip overlay above ability slots.
func key_chip_box() -> StyleBoxFlat:
	return panel_box(NIGHT_2, 4, Color(1.0, 1.0, 1.0, 0.10), 1)

# `.hb-hp-track` — narrow rounded rail for a hero's HP, dark recess.
func hp_track_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.40)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.0, 0.0, 0.0, 0.50)
	return sb

func hp_fill_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	return sb

# `.hb-pip-combat` — small all-caps red pip on the hero badge during waves.
func combat_pip_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PIP_COMBAT_BG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

# `.hb-stripe` — 4px hero-core glow on the left edge of the badge.
func hero_stripe_color(faction: String) -> Color:
	var c := core_color(faction)
	return Color(c.r, c.g, c.b, 0.85)

# `.hud-bottom` hand-strip backdrop — translucent night band the hand sits on.
func hand_backdrop_color() -> Color:
	return Color(NIGHT_0.r, NIGHT_0.g, NIGHT_0.b, 0.55)
