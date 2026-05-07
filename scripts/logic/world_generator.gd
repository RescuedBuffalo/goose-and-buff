class_name WorldGenerator extends RefCounted
##
## Pure procgen world generator (BUF-144). Stamps 5x5 chunk templates
## from data/chunks.gd onto a 5x5 chunk grid (= 25x25 tiles), centered
## on a fixed lodge plaza chunk with spawn-road chunks along the south
## edge. Returns a WorldDef-shape dict ready for the sector adapter to
## paint and the world_builder adapter to populate.
##
## Determinism: same (seed, day_index, hero_id) → same world. The seed
## is the only randomness source — RandomNumberGenerator is locally
## constructed and seeded; nothing reaches into engine globals.
##
## Reachability: every infill chunk template has an all-walkable border
## (no T/R/W on the outer ring), and the spawn-road row has its
## enemy-entry tiles open. With 4-direction AStar this guarantees the
## lodge is reachable from any spawn entry — no validate-and-retry
## loop is needed in practice. If a future template breaks the border
## rule, validation will be added at the same layer.
##
## Performance: a 25x25 stamp + ~20 resource placements completes in
## well under 250ms on the dev machine. No heavy CPU work; the cost
## is dominated by Dictionary construction.

const Chunks := preload("res://data/chunks.gd")
const WorldDefClass := preload("res://data/world_def.gd")
const Sectors := preload("res://data/sectors.gd")

# Tile-code → resource-kind map. The chunk template uses single-letter
# codes; the world def stores resource kind ids (matching data/resources.gd).
const CODE_TO_RESOURCE := {
	"T": "tree_pine",
	"R": "rock_field",
	"B": "berry_bush",
}

# Tile-code → biome tag map. The world def stores the biome the tile
# floor should be painted as; resources are layered on top via the
# `resources` array.
const CODE_TO_BIOME := {
	".": WorldDefClass.BIOME_GRASS,
	"T": WorldDefClass.BIOME_GRASS,    # tree sits on grass; the resource node is the "tree"
	"R": WorldDefClass.BIOME_GRASS,    # likewise
	"B": WorldDefClass.BIOME_GRASS,    # berry bush walkable, sits on grass
	"W": WorldDefClass.BIOME_WATER,
	"s": WorldDefClass.BIOME_SAND,
	"L": WorldDefClass.BIOME_LODGE,
	"=": WorldDefClass.BIOME_ENTRY,
}

# ── Public ───────────────────────────────────────────────────────────

static func generate(seed: int, day_index: int, hero_id: String) -> Dictionary:
	# Top-level entry. Returns a WorldDef-shape dict; never null. A seed
	# of 0 is treated as "pick any" — the caller should pass the
	# canonical seed they want to be reproducible.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Layout: 5x5 chunk grid. Chunk (2,2) = plaza; row y=4 = spawn road;
	# everything else infill picked from climate-weighted pools.
	var chunk_grid_w: int = Chunks.CHUNK_GRID.x
	var chunk_grid_h: int = Chunks.CHUNK_GRID.y
	var weights: Dictionary = Chunks.climate_weights_for_day(day_index)
	var chunks_layout: Array = []
	# Pre-stamp resolution: pick a template id for every chunk position.
	for cy in chunk_grid_h:
		for cx in chunk_grid_w:
			var pos := Vector2i(cx, cy)
			var picked: Dictionary = _pick_template_for_position(pos, rng, weights)
			chunks_layout.append({
				"chunk_pos": pos,
				"template_id": String(picked.id),
				"climate": String(picked.climate),
				"biome": Chunks.biome_for(picked),
			})
	# Stamp tiles + collect resource placements.
	var tiles: Array = _empty_tile_grid()
	var resources: Array = []
	for entry in chunks_layout:
		_stamp_chunk(entry, tiles, resources)
	# Spawn entry tiles overlay — guarantees the south spawn band is
	# painted as entry biome, even if a template's bottom row drifts.
	for tile in Sectors.ENEMY_ENTRY_TILES:
		var cell: Dictionary = tiles[tile.y][tile.x]
		cell["biome"] = WorldDefClass.BIOME_ENTRY
		# Entry tiles override any chunk-suggested resource at that position.
		resources = _strip_resource_at(resources, tile)
	# Lodge tile overlay — same logic, plus its 8-neighborhood gets
	# scrubbed of resources (the protected radius from data/sectors.gd).
	tiles[Sectors.LODGE_TILE.y][Sectors.LODGE_TILE.x]["biome"] = WorldDefClass.BIOME_LODGE
	resources = _strip_resources_in_radius(resources, Sectors.LODGE_TILE, Sectors.PROTECTED_RADIUS)
	# Stats for telemetry / debug overlay.
	var stats := {
		"chunk_count": chunks_layout.size(),
		"resource_count": resources.size(),
		"climate_distribution": _count_climates(chunks_layout),
		"biome_distribution": _count_biomes(chunks_layout),
	}
	return {
		"seed": seed,
		"day_index": day_index,
		"hero_id": hero_id,
		"tile_grid_size": Sectors.TILE_GRID_SIZE,
		"lodge_tile": Sectors.LODGE_TILE,
		"spawn_tile": Sectors.SPAWN_TILE,
		"enemy_entry_tiles": Sectors.ENEMY_ENTRY_TILES.duplicate(),
		"tiles": tiles,
		"resources": resources,
		"chunks": chunks_layout,
		"stats": stats,
	}

# ── Pickers ──────────────────────────────────────────────────────────

static func _pick_template_for_position(pos: Vector2i, rng: RandomNumberGenerator, weights: Dictionary) -> Dictionary:
	# Center chunk = lodge plaza. South row (y=4) = spawn-road (so the
	# enemy entry tiles stay open). Everything else: weighted-random
	# infill from the day's climate pool.
	if pos == Vector2i(2, 2):
		return Chunks.by_id("plaza")
	if pos.y == Chunks.CHUNK_GRID.y - 1:
		return Chunks.by_id("spawn_road")
	var climate: String = _pick_climate(rng, weights)
	var pool: Array = Chunks.infill_pool_for_climate(climate)
	if pool.is_empty():
		# Climate's pool is empty — fall back to temperate so we always
		# return something. Shouldn't fire with the current chunk set.
		pool = Chunks.infill_pool_for_climate("temperate")
	return _weighted_pick(pool, rng)

static func _pick_climate(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total: int = 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return "temperate"
	var roll: int = rng.randi_range(1, total)
	var running: int = 0
	for k in weights:
		running += int(weights[k])
		if roll <= running:
			return String(k)
	return "temperate"

static func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	for t in pool:
		total += int(t.get("weight", 10))
	if total <= 0:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll: int = rng.randi_range(1, total)
	var running: int = 0
	for t in pool:
		running += int(t.get("weight", 10))
		if roll <= running:
			return t
	return pool[0]

# ── Stamp ────────────────────────────────────────────────────────────

static func _empty_tile_grid() -> Array:
	var grid: Array = []
	for y in Sectors.TILE_GRID_SIZE.y:
		var row: Array = []
		for x in Sectors.TILE_GRID_SIZE.x:
			row.append({
				"biome": WorldDefClass.BIOME_GRASS,
				"climate": WorldDefClass.CLIMATE_TEMPERATE,
			})
		grid.append(row)
	return grid

static func _stamp_chunk(entry: Dictionary, tiles: Array, resources: Array) -> void:
	var template: Dictionary = Chunks.by_id(String(entry.template_id))
	if template.is_empty():
		return
	var cpos: Vector2i = entry.chunk_pos
	var climate: String = String(entry.climate)
	# Plaza and spawn-road chunks have climate "any" — give those tiles
	# temperate climate visually so the center reads as the lit hearth.
	var paint_climate: String = climate if climate != "any" else WorldDefClass.CLIMATE_TEMPERATE
	var rows: Array = template.tiles
	for ry in rows.size():
		var row: String = String(rows[ry])
		for rx in row.length():
			var code: String = row.substr(rx, 1)
			var tx: int = cpos.x * Chunks.CHUNK_SIZE + rx
			var ty: int = cpos.y * Chunks.CHUNK_SIZE + ry
			if tx < 0 or tx >= Sectors.TILE_GRID_SIZE.x:
				continue
			if ty < 0 or ty >= Sectors.TILE_GRID_SIZE.y:
				continue
			var biome: String = String(CODE_TO_BIOME.get(code, WorldDefClass.BIOME_GRASS))
			tiles[ty][tx] = {"biome": biome, "climate": paint_climate}
			if CODE_TO_RESOURCE.has(code):
				resources.append({
					"kind": String(CODE_TO_RESOURCE[code]),
					"tile": Vector2i(tx, ty),
				})

# ── Cleanup helpers ──────────────────────────────────────────────────

static func _strip_resource_at(resources: Array, tile: Vector2i) -> Array:
	var out: Array = []
	for r in resources:
		if Vector2i(r.tile) != tile:
			out.append(r)
	return out

static func _strip_resources_in_radius(resources: Array, center: Vector2i, radius: int) -> Array:
	var out: Array = []
	for r in resources:
		var t: Vector2i = Vector2i(r.tile)
		var dx: int = abs(t.x - center.x)
		var dy: int = abs(t.y - center.y)
		if max(dx, dy) > radius:
			out.append(r)
	return out

static func _count_climates(layout: Array) -> Dictionary:
	var counts: Dictionary = {"temperate": 0, "frosted": 0, "frozen": 0, "any": 0}
	for entry in layout:
		var c: String = String(entry.climate)
		counts[c] = int(counts.get(c, 0)) + 1
	return counts

static func _count_biomes(layout: Array) -> Dictionary:
	# Biome counts ride alongside climate counts so the debug panel can
	# show the placeholder variant breakdown (BUF-146). Empty dict, not
	# a fixed-key dict — winter_pine / ridge_cold only appear when the
	# day's pool actually rolled them.
	var counts: Dictionary = {}
	for entry in layout:
		var b: String = String(entry.get("biome", entry.climate))
		counts[b] = int(counts.get(b, 0)) + 1
	return counts

# ── Seed helpers ─────────────────────────────────────────────────────
##
## A "watch seed" is a short, human-shareable representation of the
## seed used for run-start. Keeping it lowercase-hex-ish so paste-back
## from chat doesn't trip over case.

static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi())

static func seed_to_string(seed: int) -> String:
	# Lowercase 8-char hex of the unsigned 32-bit cast — short enough to
	# share over voice and re-type without errors. We store the int
	# internally; the string is just for display/copy.
	return "%08x" % (seed & 0xFFFFFFFF)

static func string_to_seed(text: String) -> int:
	# Accept hex (with or without 0x) or decimal. Empty / unparseable
	# strings return 0, which the caller interprets as "use a random
	# seed" via random_seed().
	var s: String = text.strip_edges().to_lower()
	if s.is_empty():
		return 0
	if s.begins_with("0x"):
		s = s.substr(2)
	# Try hex first.
	if s.is_valid_hex_number():
		return int("0x" + s)
	if s.is_valid_int():
		return int(s)
	return 0
