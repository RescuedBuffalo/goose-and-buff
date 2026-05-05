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
