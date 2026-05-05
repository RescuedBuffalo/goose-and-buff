class_name SectorsData extends RefCounted
##
## Sector geometry for the survival rebuild. Coordinates are tile-space
## Vector2i. Adapters convert tile→pixel via the TileMapLayer's map_to_local.
##
## The Phase 1 wave-defense build used a 16x12 grid with the spawn pad on
## the low-x side and the core on the high-x side. The survival rebuild
## widens to 25x25 and recenters the lodge core, with terrain biomes
## seeded around it: treeline north, rocks east, water west, open ground
## south where night raids enter.
##
## Hero / enemy pathfinding treats every floor tile as walkable except
## where blocked by the lodge core, water tiles, or placed obstacles.

# ── Tile grid geometry ────────────────────────────────────────────────────
const TILE_GRID_SIZE := Vector2i(25, 25)
const TILE_PIXELS := Vector2i(64, 32)  # standard isometric ratio (2:1)

# Lodge core sits in the middle. The hero spawns one tile down (south) so
# the player sees the core from the start and the camera frames both.
const LODGE_TILE := Vector2i(12, 12)
const SPAWN_TILE := Vector2i(12, 14)

# Backwards-compat alias — the old prototype called this CORE_TILE; some
# adapters still read it during the transition. Will be cleaned up once
# every consumer is on LODGE_TILE.
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
# while the survival shape is being tested.
const CORE_HEALTH := 1000.0

# Camera frame bounds in tile space — keeps the camera from showing void
# outside the world. The adapter clamps to (margin, grid - margin).
const CAMERA_MARGIN_TILES := Vector2i(6, 4)

# ── Terrain biomes (seeded resource zones) ────────────────────────────────
##
## Biomes are descriptive: the world adapter reads these zones to decide
## where to scatter trees, rocks, bushes, and water. They are NOT a
## per-tile floor map — every tile is walkable grass by default; obstacles
## live as Node2D children placed on top.
##
## Zones overlap intentionally — a treeline can run alongside a rock
## outcrop. The adapter resolves overlaps by precedence (water > rocks >
## trees > bushes > clear) so a water tile never has a tree on it.

const BIOME_TREELINE := Rect2i(2, 1, 21, 5)         # north, wide band
const BIOME_ROCKS := Rect2i(20, 6, 5, 12)            # east outcrop
const BIOME_WATER := Rect2i(0, 6, 4, 12)             # west water cluster
const BIOME_BERRIES := Rect2i(6, 18, 13, 4)          # south-of-lodge meadow
const BIOME_OPEN := Rect2i(5, 21, 15, 4)             # south spawn-ground

# Tiles that must never have any obstacle on them — the lodge tile itself
# and its 8-neighborhood, plus the hero's spawn tile and a small breathing
# room around it. The world seeder consults this set before placing
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
	# Lodge core is the only fixed obstacle at geometry level. Water and
	# resource-node blocking are decided by the world adapter at seed-time
	# via AStar.set_point_solid; geometry treats them as terrain hints, not
	# rules.
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

static func is_in_rect(tile: Vector2i, rect: Rect2i) -> bool:
	return rect.has_point(tile)

static func biome_at(tile: Vector2i) -> String:
	# Precedence: water > rocks > trees > berries > open. Adapter uses
	# this to pick a tile color and decide what (if anything) to place.
	if is_in_rect(tile, BIOME_WATER):
		return "water"
	if is_in_rect(tile, BIOME_ROCKS):
		return "rocks"
	if is_in_rect(tile, BIOME_TREELINE):
		return "trees"
	if is_in_rect(tile, BIOME_BERRIES):
		return "berries"
	if is_in_rect(tile, BIOME_OPEN):
		return "open"
	return "grass"
