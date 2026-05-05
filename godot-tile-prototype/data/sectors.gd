class_name SectorsData extends RefCounted
##
## Sector geometry for the tile rebuild. All coordinates are tile-space
## Vector2i. The adapter (sector.gd) owns the TileMap and converts tile
## coords to screen pixels via map_to_local(). The original top-down
## prototype stored pixel anchors here directly — that's what changed.
##
## Tile layout for v0 (Buffalo single-sector):
##   16 wide × 12 tall, isometric DIAMOND_DOWN.
##   Spawn pad on the low-x side; core anchored mid-grid on the high-x
##   side; enemies enter from the high-x edge and walk toward the core.
##
## Hero / unit pathfinding treats every floor tile as walkable. The core
## tile is the only blocker — enemies stop at adjacent tiles and attack.

# ── Tile grid geometry ────────────────────────────────────────────────────
const TILE_GRID_SIZE := Vector2i(16, 12)
const TILE_PIXELS := Vector2i(64, 32)  # standard isometric ratio (2:1)

# Special tiles. Tile coords (x, y) → adapter converts via map_to_local().
const SPAWN_TILE := Vector2i(1, 6)
const CORE_TILE := Vector2i(14, 6)
const ENEMY_ENTRY_TILES: Array[Vector2i] = [
	Vector2i(15, 5),
	Vector2i(15, 6),
	Vector2i(15, 7),
]

# Building (Production Node) snap target. Sits adjacent to the spawn pad
# so the resource trickle stays behind the line. Drop-targeting still goes
# anywhere; this is the visual anchor used when no drop position is given.
const PRODUCTION_NODE_DEFAULT_TILE := Vector2i(2, 6)

# Core HP — same value as the top-down prototype. The tile rebuild changes
# the rendering, not the balance.
const CORE_HEALTH := 1000.0

# ── Hand band reserve ─────────────────────────────────────────────────────
# Bottom 320 px of the 1080 viewport hosts the card hand. Sector tiles paint
# above this band; the camera respects it via the WORLD_OFFSET below.
const HAND_BAND_HEIGHT := 320

# Where the TileMap origin sits in viewport pixels. Centered horizontally;
# pulled up from vertical center so the diamond bounding box (which is taller
# than tall when 16w×12t) sits above the hand band.
const WORLD_OFFSET := Vector2(960.0, 280.0)

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
	# Core tile is the one fixed obstacle. Enemies stop adjacent to it.
	return tile == CORE_TILE

static func all_floor_tiles() -> Array[Vector2i]:
	# Used by the adapter to paint the floor cells once at sector build.
	var out: Array[Vector2i] = []
	for x in TILE_GRID_SIZE.x:
		for y in TILE_GRID_SIZE.y:
			out.append(Vector2i(x, y))
	return out
