class_name SectorsData extends RefCounted
##
## Sector geometry. Coordinates are tile-space Vector2i. Adapters
## convert tile→pixel via the TileMapLayer's map_to_local.
##
## After M2 (BUF-144), terrain is no longer hand-crafted here — the
## procgen world generator (scripts/logic/world_generator.gd) produces
## a WorldDef that the sector adapter consumes. This file keeps only
## the *fixed* geometry: grid size, tile pixel ratio, lodge/spawn/entry
## tiles, hero palette keys.

# ── Tile grid geometry ────────────────────────────────────────────────────
const TILE_GRID_SIZE := Vector2i(25, 25)
const TILE_PIXELS := Vector2i(64, 32)  # standard isometric ratio (2:1)

# Lodge core sits in the middle. The hero spawns one tile down (south) so
# the player sees the core from the start and the camera frames both.
const LODGE_TILE := Vector2i(12, 12)
const SPAWN_TILE := Vector2i(12, 14)

# Backwards-compat alias — the old prototype called this CORE_TILE.
const CORE_TILE := LODGE_TILE

# Default tile the (deprecated) production node card snapped to when the
# old card-hand flow placed it. Kept so legacy logic doesn't crash; the
# survival rebuild places via the inventory + ghost-overlay flow instead.
const PRODUCTION_NODE_DEFAULT_TILE := Vector2i(11, 13)

# South-edge tiles where wolves enter on night phases. Wider band than
# the old 3-tile gate so the line spreads out and has to be defended.
const ENEMY_ENTRY_TILES: Array[Vector2i] = [
	Vector2i(8, 24),
	Vector2i(10, 24),
	Vector2i(12, 24),
	Vector2i(14, 24),
	Vector2i(16, 24),
]

# Lodge core HP — same value as the wave-defense build so balance carries
# while the survival shape is being tested. (M2 stat upgrades modulate
# this via the lodge_hp_max stat.)
const CORE_HEALTH := 1000.0

# Camera frame bounds in tile space — keeps the camera from showing void
# outside the world. The adapter clamps to (margin, grid - margin).
const CAMERA_MARGIN_TILES := Vector2i(6, 4)

# Tiles that must never have any obstacle on them — the lodge tile itself
# and its 8-neighborhood, plus the hero's spawn tile and a small breathing
# room around it. The world generator consults this set before placing
# resource nodes.
const PROTECTED_RADIUS := 2  # Chebyshev distance from LODGE_TILE

# ── Hero palette keys ─────────────────────────────────────────────────────
const Buffalo := {
	"id": "Buffalo",
	"floor_color_key": "Buffalo",
	"core_color_key": "Buffalo",
}

const Goose := {
	"id": "Goose",
	"floor_color_key": "Goose",
	"core_color_key": "Goose",
}

const Fox := {
	"id": "Fox",
	"floor_color_key": "Fox",
	"core_color_key": "Fox",
}

const BY_HERO := {
	"Buffalo": Buffalo,
	"Goose": Goose,
	"Fox": Fox,
}

# ── Helpers ───────────────────────────────────────────────────────────────
static func is_tile_in_grid(tile: Vector2i) -> bool:
	return (tile.x >= 0 and tile.x < TILE_GRID_SIZE.x
		and tile.y >= 0 and tile.y < TILE_GRID_SIZE.y)

static func is_tile_blocked(tile: Vector2i) -> bool:
	# Lodge core is the only fixed obstacle at geometry level. Resource
	# blocking and water tiles are decided by the world generator and
	# applied via AStar.set_point_solid in the sector adapter.
	return tile == LODGE_TILE

static func is_tile_protected(tile: Vector2i) -> bool:
	# Nothing should be placed on the lodge or its breathing room.
	var dx: int = abs(tile.x - LODGE_TILE.x)
	var dy: int = abs(tile.y - LODGE_TILE.y)
	return max(dx, dy) <= PROTECTED_RADIUS

static func all_floor_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in TILE_GRID_SIZE.x:
		for y in TILE_GRID_SIZE.y:
			out.append(Vector2i(x, y))
	return out
