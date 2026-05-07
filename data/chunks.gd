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
## Biome tags (BUF-146): finer-grained variants under each climate
## tier — "temperate" | "frosted" | "frozen" | "winter_pine" |
## "ridge_cold". Locked seasonal-frame language (first frost → the
## long cold → the deep dark → before the thaw) maps to the climate
## tier; biome is the placeholder slot that gives a single tier a
## couple of distinct chunk shapes so a frosted day doesn't always
## look like the same five chunks. winter_pine sits inside the
## frosted pool; ridge_cold sits inside the frozen pool.
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
##   biome: "temperate" | "frosted" | "frozen" | "winter_pine" |
##          "ridge_cold" | "any" — finer-grained placeholder variant
##          that rides on top of climate (BUF-146). Defaults to climate
##          when a template doesn't set it (use biome_for() to read).
##   role: "infill" | "plaza" | "spawn_road"
##   weight: int — relative likelihood within its climate (default 10)
##   tiles: Array[String] — 5 rows, 5 chars each, top-down

const ALL := [
	# ── Plaza (used at center, fixed) ─────────────────────────────
	{
		"id": "plaza",
		"climate": "any",
		"biome": "any",
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
		"biome": "any",
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
		"biome": "temperate",
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
		"biome": "temperate",
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
		"biome": "temperate",
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
		"biome": "temperate",
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
		"biome": "temperate",
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
		"biome": "frosted",
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
		"biome": "frosted",
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
		"biome": "frosted",
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
		"biome": "frosted",
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
	# winter_pine — denser conifer wedge under the frosted pool. Reads
	# as a "later in the season" pocket that's heavier than the bare
	# thin_treeline but still within the frosted tier. Border kept open
	# per the reachability rule.
	{
		"id": "winter_pine_stand",
		"climate": "frosted",
		"biome": "winter_pine",
		"role": "infill",
		"weight": 8,
		"tiles": [
			".....",
			".TBT.",
			"..T..",
			".TBT.",
			".....",
		],
	},
	# ── Frozen infill ────────────────────────────────────────────
	{
		"id": "frozen_pond",
		"climate": "frozen",
		"biome": "frozen",
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
		"biome": "frozen",
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
		"biome": "frozen",
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
		"biome": "frozen",
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
	# ridge_cold — high-rock spine under the frozen pool. Two-rock walls
	# that aren't quite a corridor pinch (interior still has lateral
	# escape routes) so AStar treats them as terrain colour rather than
	# choke points.
	{
		"id": "ridge_cold_spine",
		"climate": "frozen",
		"biome": "ridge_cold",
		"role": "infill",
		"weight": 8,
		"tiles": [
			".....",
			".R.R.",
			".....",
			".R.R.",
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

static func biome_for(template: Dictionary) -> String:
	# Templates added before BUF-146 don't have a `biome` key — fall
	# back to climate so callers always get a non-empty tag.
	var b: String = String(template.get("biome", ""))
	if not b.is_empty():
		return b
	return String(template.get("climate", ""))
