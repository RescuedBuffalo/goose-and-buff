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
