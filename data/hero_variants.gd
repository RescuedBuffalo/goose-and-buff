class_name HeroVariants extends RefCounted
##
## Hero variant pool (BUF-129). Each hero has a small pool of variants;
## one is randomly assigned per run via SaveIo.assign_variant_for_run.
## Players notice they're "dressed differently for the same watch" without
## any UI announcement.
##
## Per BUF-129's ticket: art lives in M3 (Scenario Recipe B + the asset
## pipeline), but the *system* that consumes the variants ships now. With
## no portrait textures yet, each variant carries:
##   id           — stable lower-snake key, persisted in save_state
##   hero         — Buffalo / Goose / Fox
##   label        — dev-private name (NOT shown in-game per "no UI
##                  announcement" rule). Useful for save-file inspection
##                  and the F3 debug overlay if we surface it later.
##   tint         — Color the hero adapter applies as sprite.modulate so
##                  the variant is visibly different across runs even
##                  before the M3 art swap. Subtle — multiplies the totem
##                  texture rather than replacing it.
##   accent       — secondary swatch surfaced on the hero-select buttons
##                  so players see *something* differs even at the menu,
##                  even though we don't tell them what.
##
## Once M3 art lands, replace `tint` with a `texture` field per variant
## and update hero.gd's _load_sprite() to pick the variant texture. The
## variant ids carry over — saves stay valid.
##
## Variant ids stay stable across art revisions (unlike texture paths)
## so a save written today round-trips after the asset pipeline ships.
## If a variant is ever retired, leave its id in place and let the lookup
## fall back to the canonical look — better than invalidating saves.

const HERO_BUFFALO := "Buffalo"
const HERO_GOOSE := "Goose"
const HERO_FOX := "Fox"

# Subtle tints — variant should land as "different scarf / palette" not
# "different character". Lerp toward the variant accent at a low strength
# so the totem still reads as itself.
const TINT_STRENGTH := 0.18

const ALL := [
	# ── Buffalo ───────────────────────────────────────────────────────────
	{
		"id": "buffalo_canonical",
		"hero": HERO_BUFFALO,
		"label": "Canonical (rust hide)",
		"tint": Color(1.0, 1.0, 1.0, 1.0),
		"accent": Color8(150, 100, 70),
	},
	{
		"id": "buffalo_winter_cloak",
		"hero": HERO_BUFFALO,
		"label": "Winter cloak (slate)",
		"tint": Color(0.84, 0.86, 0.92, 1.0),
		"accent": Color8(108, 118, 134),
	},
	{
		"id": "buffalo_lantern_oil",
		"hero": HERO_BUFFALO,
		"label": "Lantern oil (ember)",
		"tint": Color(1.06, 0.96, 0.84, 1.0),
		"accent": Color8(204, 152, 92),
	},
	{
		"id": "buffalo_pine_smoke",
		"hero": HERO_BUFFALO,
		"label": "Pine smoke (moss)",
		"tint": Color(0.92, 0.98, 0.88, 1.0),
		"accent": Color8(118, 138, 96),
	},

	# ── Goose ─────────────────────────────────────────────────────────────
	{
		"id": "goose_canonical",
		"hero": HERO_GOOSE,
		"label": "Canonical (yolk)",
		"tint": Color(1.0, 1.0, 1.0, 1.0),
		"accent": Color8(252, 222, 40),
	},
	{
		"id": "goose_dawn_blue",
		"hero": HERO_GOOSE,
		"label": "Dawn blue scarf",
		"tint": Color(0.94, 0.97, 1.04, 1.0),
		"accent": Color8(132, 168, 218),
	},
	{
		"id": "goose_storm_grey",
		"hero": HERO_GOOSE,
		"label": "Storm grey trim",
		"tint": Color(0.92, 0.92, 0.94, 1.0),
		"accent": Color8(150, 156, 168),
	},
	{
		"id": "goose_red_yarn",
		"hero": HERO_GOOSE,
		"label": "Red yarn cap",
		"tint": Color(1.04, 0.96, 0.94, 1.0),
		"accent": Color8(196, 84, 76),
	},

	# ── Fox ───────────────────────────────────────────────────────────────
	{
		"id": "fox_canonical",
		"hero": HERO_FOX,
		"label": "Canonical (orange brush)",
		"tint": Color(1.0, 1.0, 1.0, 1.0),
		"accent": Color8(248, 130, 30),
	},
	{
		"id": "fox_arctic",
		"hero": HERO_FOX,
		"label": "Arctic coat",
		"tint": Color(0.96, 0.98, 1.02, 1.0),
		"accent": Color8(212, 222, 232),
	},
	{
		"id": "fox_charcoal_mask",
		"hero": HERO_FOX,
		"label": "Charcoal mask",
		"tint": Color(0.92, 0.92, 0.94, 1.0),
		"accent": Color8(82, 78, 92),
	},
	{
		"id": "fox_birch_pelt",
		"hero": HERO_FOX,
		"label": "Birch-pelt vest",
		"tint": Color(1.02, 1.0, 0.94, 1.0),
		"accent": Color8(186, 168, 132),
	},
]

static func by_id(variant_id: String) -> Dictionary:
	for v in ALL:
		if String(v.id) == variant_id:
			return v
	return {}

static func for_hero(hero_id: String) -> Array:
	var out: Array = []
	for v in ALL:
		if String(v.hero) == hero_id:
			out.append(v)
	return out

static func tint_for(variant_id: String) -> Color:
	var v: Dictionary = by_id(variant_id)
	if v.is_empty():
		return Color(1, 1, 1, 1)
	return v.get("tint", Color(1, 1, 1, 1))

static func accent_for(variant_id: String) -> Color:
	var v: Dictionary = by_id(variant_id)
	if v.is_empty():
		return Color(1, 1, 1, 1)
	return v.get("accent", Color(1, 1, 1, 1))
