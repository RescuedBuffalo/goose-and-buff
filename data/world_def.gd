class_name WorldDef extends RefCounted
##
## Plain-data shape returned by world_generator.gd. Pure data — no engine
## refs, no scene-tree access. Adapters consume the dict and stamp it into
## the scene tree.
##
## Shape:
##   {
##     "seed": int,
##     "day_index": int,
##     "hero_id": String,
##     "tile_grid_size": Vector2i,
##     "lodge_tile": Vector2i,
##     "spawn_tile": Vector2i,
##     "enemy_entry_tiles": Array[Vector2i],
##     "tiles": Array[Array[Dictionary]],   # tiles[y][x] = {biome, climate}
##     "resources": Array[Dictionary],      # [{kind: String, tile: Vector2i}]
##     "chunks": Array[Dictionary],         # debug overlay metadata
##     "stats": Dictionary,                 # {chunk_count, resource_count, etc}
##   }
##
## Each cell in `tiles` is {biome, climate} where:
##   biome  ∈ {"grass", "trees", "rocks", "berries", "water", "lodge",
##             "entry", "sand"}
##   climate ∈ {"temperate", "frosted", "frozen"}
##
## The biome value tells the painter which atlas tile to use; climate
## tells it how to tint. Resource nodes are NOT tiles — they spawn as
## Node2Ds at `resources[i].tile`.

const BIOME_GRASS := "grass"
const BIOME_TREES := "trees"
const BIOME_ROCKS := "rocks"
const BIOME_BERRIES := "berries"
const BIOME_WATER := "water"
const BIOME_LODGE := "lodge"
const BIOME_ENTRY := "entry"
const BIOME_SAND := "sand"

const CLIMATE_TEMPERATE := "temperate"
const CLIMATE_FROSTED := "frosted"
const CLIMATE_FROZEN := "frozen"

static func tile_at(world: Dictionary, tile: Vector2i) -> Dictionary:
	var grid: Array = world.get("tiles", [])
	if tile.y < 0 or tile.y >= grid.size():
		return {"biome": BIOME_GRASS, "climate": CLIMATE_TEMPERATE}
	var row: Array = grid[tile.y]
	if tile.x < 0 or tile.x >= row.size():
		return {"biome": BIOME_GRASS, "climate": CLIMATE_TEMPERATE}
	return row[tile.x]

static func biome_at(world: Dictionary, tile: Vector2i) -> String:
	return String(tile_at(world, tile).get("biome", BIOME_GRASS))

static func climate_at(world: Dictionary, tile: Vector2i) -> String:
	return String(tile_at(world, tile).get("climate", CLIMATE_TEMPERATE))

static func is_blocking_biome(biome: String) -> bool:
	# Water blocks pathing as terrain. Tree / rock tiles only show the
	# biome floor — the actual blocker is the Node2D resource on top of
	# the tile, which sets the AStar point solid via the world builder.
	return biome == BIOME_WATER
