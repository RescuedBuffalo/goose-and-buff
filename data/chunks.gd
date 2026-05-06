class_name ChunksData extends RefCounted
##
## Chunk-template catalog for procgen worlds (BUF-144).
##
## Each template is a 5x5 grid of single-character tile codes plus a
## climate tag. The world generator stamps templates onto a 5x5 chunk
## grid (= 25x25 tile world) and stitches them with a lodge-plaza in
## the center and spawn-road chunks along the south edge.
##
## Tile codes:
##   . — open ground (walkable, climate-tinted grass)
##   T — tree resource node (blocks movement, gathers wood)
##   R — rock resource node (blocks movement, gathers stone)
##   B — berry bush (walkable, gathers berries)
##   W — water (impassable terrain)
##   s — sand / beach (walkable, drawn warm)
##   L — lodge core (special, only used in the plaza)
##   = — entry road (walkable, drawn warm)
##
## Climate tags (BUF-146): "temperate" | "frosted" | "frozen". The
## generator picks chunks weighted by the day's climate distribution;
## the renderer tints tiles by the chunk's climate. Resources spawn
## the same in any climate — frozen woods still drop wood; the look
## is what changes.
##
## Design rule: chunk borders are ALWAYS walkable (no `T`, `R`, or
## `W` on the outer ring of any non-center chunk). With 4-direction
## AStar, this guarantees lodge reachability from any spawn entry
## without an expensive validation step. Resource clusters live in
## the chunk interior.

const CHUNK_SIZE := 5
const CHUNK_GRID := Vector2i(5, 5)

# Climate distribution by day_index — picks weighted-randomly when
# stamping non-fixed chunks. Day 1 reads as late-fall temperate; day 3
# reads as deep frozen. Numbers don't have to add to 100, the
# generator normalizes.
const CLIMATE_WEIGHTS_BY_DAY := {
	1: {"temperate": 70, "frosted": 25, "frozen": 5},
	2: {"temperate": 30, "frosted": 50, "frozen": 20},
	3: {"temperate": 10, "frosted": 40, "frozen": 50},
}

# ── Templates ────────────────────────────────────────────────────────
##
## Each template:
##   id: String — stable identifier for telemetry / debug
##   climate: "temperate" | "frosted" | "frozen" | "any"
##   role: "infill" | "plaza" | "spawn_road"
##   weight: int — relative likelihood within its climate (default 10)
##   tiles: Array[String] — 5 rows, 5 chars each, top-down

const ALL := [
	# ── Plaza (used at center, fixed) ─────────────────────────────
	{
		"id": "plaza",
		"climate": "any",
		"role": "plaza",
		"weight": 0,
		"tiles": [
			".....",
			".....",
			"..L..",
			".....",
			".....",
		],
	},
	# ── Spawn road (used in south row, ensures entry tiles open) ──
	{
		"id": "spawn_road",
		"climate": "any",
		"role": "spawn_road",
		"weight": 0,
		"tiles": [
			".....",
			".....",
			".....",
			".....",
			"=.=.=",
		],
	},
	# ── Temperate infill ─────────────────────────────────────────
	{
		"id": "open_glade",
		"climate": "temperate",
		"role": "infill",
		"weight": 12,
		"tiles": [
			".....",
			".....",
			"..B..",
			".....",
			".....",
		],
	},
	{
		"id": "scattered_pine",
		"climate": "temperate",
		"role": "infill",
		"weight": 14,
		"tiles": [
			".....",
			".T...",
			"...T.",
			".T.T.",
			".....",
		],
	},
	{
		"id": "berry_meadow",
		"climate": "temperate",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			".B.B.",
			".....",
			".B.B.",
			".....",
		],
	},
	{
		"id": "low_rocks",
		"climate": "temperate",
		"role": "infill",
		"weight": 8,
		"tiles": [
			".....",
			".R...",
			"...R.",
			".....",
			"..R..",
		],
	},
	{
		"id": "mixed_brush",
		"climate": "temperate",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			".T.B.",
			".....",
			".B.T.",
			".....",
		],
	},
	# ── Frosted infill ───────────────────────────────────────────
	{
		"id": "frosted_grove",
		"climate": "frosted",
		"role": "infill",
		"weight": 12,
		"tiles": [
			".....",
			".T.T.",
			"..T..",
			".T.T.",
			".....",
		],
	},
	{
		"id": "frosted_rocks",
		"climate": "frosted",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			"..R..",
			".R.R.",
			"..R..",
			".....",
		],
	},
	{
		"id": "stillpond",
		"climate": "frosted",
		"role": "infill",
		"weight": 8,
		"tiles": [
			".....",
			".sWs.",
			".WWW.",
			".sWs.",
			".....",
		],
	},
	{
		"id": "thin_treeline",
		"climate": "frosted",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			"..T..",
			".....",
			"...T.",
			"..T..",
		],
	},
	# ── Frozen infill ────────────────────────────────────────────
	{
		"id": "frozen_pond",
		"climate": "frozen",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			".WWW.",
			".WWW.",
			".WWW.",
			".....",
		],
	},
	{
		"id": "dead_stand",
		"climate": "frozen",
		"role": "infill",
		"weight": 10,
		"tiles": [
			".....",
			".T...",
			"...T.",
			".....",
			"..T..",
		],
	},
	{
		"id": "rimed_outcrop",
		"climate": "frozen",
		"role": "infill",
		"weight": 12,
		"tiles": [
			".....",
			".R.R.",
			"..R..",
			".R.R.",
			".....",
		],
	},
	{
		"id": "frozen_clearing",
		"climate": "frozen",
		"role": "infill",
		"weight": 8,
		"tiles": [
			".....",
			".....",
			"..R..",
			".....",
			".....",
		],
	},
]

# ── Lookups ──────────────────────────────────────────────────────────

static func by_id(id: String) -> Dictionary:
	for t in ALL:
		if String(t.id) == id:
			return t
	return {}

static func infill_pool_for_climate(climate: String) -> Array:
	var out: Array = []
	for t in ALL:
		if String(t.role) != "infill":
			continue
		if String(t.climate) == climate:
			out.append(t)
	return out

static func climate_weights_for_day(day_index: int) -> Dictionary:
	# Days beyond 3 just keep day-3 weights — we only ship 3-night runs
	# but defensive lookup keeps the function honest for tests.
	return CLIMATE_WEIGHTS_BY_DAY.get(day_index, CLIMATE_WEIGHTS_BY_DAY[3])
