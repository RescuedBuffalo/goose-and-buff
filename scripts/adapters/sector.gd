extends Node2D
##
## Sector adapter — owns the TileMapLayer, the procedurally-built
## TileSet, and the AStarGrid2D pathfinding graph. After M2 (BUF-144),
## the sector is purely an adapter: it consumes a WorldDef from the
## world generator and paints + builds AStar from that.
##
## Resource nodes (trees / rocks / bushes) are NOT tiles — they are
## Node2D children placed on top by the world_builder adapter. The
## sector exposes block_tile / unblock_tile so those adapters can
## hook into AStar without reaching across layers.
##
## Tile coords come from data/sectors.gd. The atlas is procedural so
## the prototype runs without imported tile artwork; tile colors per
## (biome, climate) come from a token-driven palette so design adjusts
## the look without editor work.

const Sectors := preload("res://data/sectors.gd")
const WorldDefClass := preload("res://data/world_def.gd")

signal core_destroyed()
signal core_hp_changed(current: float, maximum: float)

# Atlas coordinates — one row of (biome × climate) variants in the
# procedural texture. Climate band offset on the y-axis lets the same
# biome tile shift between temperate/frosted/frozen tinting without a
# per-tile shader.
const BIOMES_IN_ORDER := [
	WorldDefClass.BIOME_GRASS,
	WorldDefClass.BIOME_LODGE,
	WorldDefClass.BIOME_ENTRY,
	WorldDefClass.BIOME_WATER,
	WorldDefClass.BIOME_SAND,
	WorldDefClass.BIOME_TREES,
	WorldDefClass.BIOME_ROCKS,
	WorldDefClass.BIOME_BERRIES,
]

const CLIMATES_IN_ORDER := [
	WorldDefClass.CLIMATE_TEMPERATE,
	WorldDefClass.CLIMATE_FROSTED,
	WorldDefClass.CLIMATE_FROZEN,
]

const SOURCE_ID := 0

var hero_id: String = "Buffalo"
var core_hp: float = Sectors.CORE_HEALTH
var core_hp_max: float = Sectors.CORE_HEALTH
var astar: AStarGrid2D
var _tile_layer: TileMapLayer
var _build_highlight_tile: Vector2i = Vector2i(-1, -1)
var _build_highlight_valid: bool = true

# Cached world def from the generator. Stored so debug overlays and
# downstream lookups can read climate/biome without re-querying.
var world_def: Dictionary = {}

func _ready() -> void:
	add_to_group("sector")
	# The world is now larger than the screen — anchor the TileMap at
	# (0,0) and let the camera pan over it, instead of pre-centering.
	position = Vector2.ZERO
	_tile_layer = TileMapLayer.new()
	_tile_layer.tile_set = _build_tile_set(hero_id)
	_tile_layer.y_sort_enabled = true
	# Ground layer sits below everything else (z=-1). Without this, the
	# cascading y_sort_enabled chain (Main → Sector → TileMapLayer)
	# treats tiles + characters + characters' shadows as one big Y-sort
	# batch, so a tile south of the hero (higher world Y) draws AFTER
	# Hero+Shadow and paints over the shadow's southern edge. Pushing
	# the whole tile layer to z_index = -1 keeps tiles strictly under
	# every default-z entity (characters, props, shadows) while letting
	# props at z=0 continue Y-sorting among themselves (so a tree south
	# of the hero still occludes him correctly).
	_tile_layer.z_index = -1
	add_child(_tile_layer)

# ── Identity ──────────────────────────────────────────────────────────────
func set_hero(new_hero_id: String) -> void:
	if hero_id == new_hero_id:
		return
	hero_id = new_hero_id
	if _tile_layer != null:
		_tile_layer.tile_set = _build_tile_set(hero_id)
		if not world_def.is_empty():
			_paint_floor_from_world(world_def)
	queue_redraw()

# ── World def adoption ──────────────────────────────────────────────────
##
## Called by main.gd after world_generator.generate() runs. Re-paints
## the tile layer and rebuilds AStar from the def's tile grid + lodge
## tile + water tiles.

func adopt_world(def: Dictionary) -> void:
	world_def = def
	_paint_floor_from_world(def)
	_build_astar_from_world(def)
	queue_redraw()

# ── Tile coordinate API ───────────────────────────────────────────────────
func tile_to_world(tile: Vector2i) -> Vector2:
	return _tile_layer.to_global(_tile_layer.map_to_local(tile))

func world_to_tile(world: Vector2) -> Vector2i:
	return _tile_layer.local_to_map(_tile_layer.to_local(world))

func clamp_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		clamp(tile.x, 0, Sectors.TILE_GRID_SIZE.x - 1),
		clamp(tile.y, 0, Sectors.TILE_GRID_SIZE.y - 1),
	)

func is_tile_walkable(tile: Vector2i) -> bool:
	if not Sectors.is_tile_in_grid(tile):
		return false
	if astar == null:
		return true
	return not astar.is_point_solid(tile)

# Building, resource, and water tiles set themselves solid in AStar via
# this helper. The sector treats AStar as the source of truth for "can
# I path through this tile" — biome painting is purely cosmetic.
func block_tile(tile: Vector2i) -> void:
	if astar == null or not Sectors.is_tile_in_grid(tile):
		return
	astar.set_point_solid(tile, true)

func unblock_tile(tile: Vector2i) -> void:
	if astar == null or not Sectors.is_tile_in_grid(tile):
		return
	astar.set_point_solid(tile, false)

# ── Pathfinding ───────────────────────────────────────────────────────────
func find_path(from_tile: Vector2i, to_tile: Vector2i) -> Array:
	if from_tile == to_tile:
		return []
	if not Sectors.is_tile_in_grid(from_tile):
		return []
	var goal := to_tile
	if not Sectors.is_tile_in_grid(goal):
		return []
	if astar.is_point_solid(goal):
		var fallback := _nearest_walkable_neighbor(goal, from_tile)
		if fallback == goal:
			return []
		goal = fallback
	var raw := astar.get_id_path(from_tile, goal)
	if raw.size() <= 1:
		return []
	var stripped: Array = []
	for i in range(1, raw.size()):
		stripped.append(raw[i])
	return stripped

func tile_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _nearest_walkable_neighbor(target: Vector2i, from_tile: Vector2i) -> Vector2i:
	var candidates: Array = [
		target + Vector2i(-1, 0),
		target + Vector2i(1, 0),
		target + Vector2i(0, -1),
		target + Vector2i(0, 1),
	]
	var best: Vector2i = target
	var best_d := INF
	for c in candidates:
		if not Sectors.is_tile_in_grid(c):
			continue
		if astar.is_point_solid(c):
			continue
		var d: float = float(abs(c.x - from_tile.x) + abs(c.y - from_tile.y))
		if d < best_d:
			best_d = d
			best = c
	return best

# ── Core HP ───────────────────────────────────────────────────────────────
func damage_core(amount: float) -> void:
	core_hp = max(0.0, core_hp - amount)
	GameState.set_core_hp(core_hp, core_hp_max)
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()
	if core_hp <= 0.0:
		core_destroyed.emit()

func reset_core(max_hp: float = -1.0) -> void:
	# Optional max_hp lets stat-system upgrades scale lodge HP per run
	# without the sector knowing about the upgrade pool. -1 means "use
	# the existing max" (back-compat default).
	if max_hp > 0.0:
		core_hp_max = max_hp
	core_hp = core_hp_max
	GameState.set_core_hp(core_hp, core_hp_max)
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()

# ── Build ghost ──────────────────────────────────────────────────────────
func set_build_ghost(tile: Vector2i, valid: bool) -> void:
	if _build_highlight_tile == tile and _build_highlight_valid == valid:
		return
	_build_highlight_tile = tile
	_build_highlight_valid = valid
	queue_redraw()

func clear_build_ghost() -> void:
	if _build_highlight_tile == Vector2i(-1, -1):
		return
	_build_highlight_tile = Vector2i(-1, -1)
	queue_redraw()

# ── Visuals ───────────────────────────────────────────────────────────────
func _draw() -> void:
	# Lodge HP bar above the lodge tile.
	var core_world := _tile_layer.map_to_local(Sectors.LODGE_TILE)
	var bar_w := 96.0
	var bar_h := 5.0
	var bar_x := core_world.x - bar_w * 0.5
	var bar_y := core_world.y - 36.0
	var hp_ratio: float = 0.0 if core_hp_max == 0 else core_hp / core_hp_max
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h), DesignTokens.hp_color(hp_ratio), true)
	# Build ghost — diamond outline at the cursor tile.
	if _build_highlight_tile != Vector2i(-1, -1):
		var color: Color = DesignTokens.HP_FULL if _build_highlight_valid else DesignTokens.HP_CRIT
		var outline := Color(color.r, color.g, color.b, 0.7)
		_draw_diamond_outline(_tile_layer.map_to_local(_build_highlight_tile), outline, 3.0)

func _draw_diamond_outline(center: Vector2, color: Color, width: float) -> void:
	var half_w := float(Sectors.TILE_PIXELS.x) * 0.5
	var half_h := float(Sectors.TILE_PIXELS.y) * 0.5
	var top := center + Vector2(0, -half_h)
	var right := center + Vector2(half_w, 0)
	var bottom := center + Vector2(0, half_h)
	var left := center + Vector2(-half_w, 0)
	draw_line(top, right, color, width)
	draw_line(right, bottom, color, width)
	draw_line(bottom, left, color, width)
	draw_line(left, top, color, width)

# ── TileSet construction (placeholder atlas) ─────────────────────────────
func _build_tile_set(hero: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Sectors.TILE_PIXELS
	var atlas := TileSetAtlasSource.new()
	atlas.texture = _build_atlas_texture(hero)
	atlas.texture_region_size = Sectors.TILE_PIXELS
	for cy in CLIMATES_IN_ORDER.size():
		for bx in BIOMES_IN_ORDER.size():
			atlas.create_tile(Vector2i(bx, cy))
	ts.add_source(atlas, SOURCE_ID)
	return ts

func _build_atlas_texture(hero: String) -> Texture2D:
	var tw: int = Sectors.TILE_PIXELS.x
	var th: int = Sectors.TILE_PIXELS.y
	var biome_count: int = BIOMES_IN_ORDER.size()
	var climate_count: int = CLIMATES_IN_ORDER.size()
	var img := Image.create(tw * biome_count, th * climate_count, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for cy in climate_count:
		var climate: String = CLIMATES_IN_ORDER[cy]
		for bx in biome_count:
			var biome: String = BIOMES_IN_ORDER[bx]
			var pair: Array = _palette_for(biome, climate, hero)
			_paint_diamond(img, bx * tw, cy * th, tw, th, pair[0], pair[1])
	return ImageTexture.create_from_image(img)

func _palette_for(biome: String, climate: String, hero: String) -> Array:
	# Token-driven biome × climate palette (BUF-146). Temperate is the
	# canonical warm palette; frosted blends toward pale-blue; frozen
	# pushes further into ice-blue. Lodge / entry tiles ignore climate
	# (they read as fixed beats on the map). All colour values live in
	# DesignTokens so design can retune without touching the painter.
	match biome:
		WorldDefClass.BIOME_LODGE:
			return [DesignTokens.core_color(hero), DesignTokens.NIGHT_0]
		WorldDefClass.BIOME_ENTRY:
			return [
				Color(DesignTokens.HP_CRIT.r, DesignTokens.HP_CRIT.g, DesignTokens.HP_CRIT.b, 0.55),
				DesignTokens.NIGHT_0,
			]
		WorldDefClass.BIOME_WATER:
			return _climate_shift([DesignTokens.BIOME_WATER_FILL, DesignTokens.BIOME_WATER_EDGE], climate)
		WorldDefClass.BIOME_SAND:
			return _climate_shift([DesignTokens.BIOME_SAND_FILL, DesignTokens.BIOME_SAND_EDGE], climate)
		WorldDefClass.BIOME_TREES:
			return _climate_shift([DesignTokens.BIOME_TREES_FILL, DesignTokens.BIOME_TREES_EDGE], climate)
		WorldDefClass.BIOME_ROCKS:
			return _climate_shift([DesignTokens.BIOME_ROCKS_FILL, DesignTokens.BIOME_ROCKS_EDGE], climate)
		WorldDefClass.BIOME_BERRIES:
			return _climate_shift([DesignTokens.BIOME_BERRIES_FILL, DesignTokens.BIOME_BERRIES_EDGE], climate)
		_:  # grass + fallback
			return _climate_shift([DesignTokens.BIOME_GRASS_FILL, DesignTokens.BIOME_GRASS_EDGE], climate)

func _climate_shift(pair: Array, climate: String) -> Array:
	# Linear blend toward a cool tint. Frosted is a gentle shift; frozen
	# is a strong shift — the player should feel the cold deepen across
	# the world even before real per-biome art lands in M3.
	var fill: Color = pair[0]
	var edge: Color = pair[1]
	match climate:
		WorldDefClass.CLIMATE_FROSTED:
			fill = fill.lerp(DesignTokens.CLIMATE_FROST_TINT, DesignTokens.CLIMATE_FROST_FILL_STRENGTH)
			edge = edge.lerp(DesignTokens.CLIMATE_FROST_TINT, DesignTokens.CLIMATE_FROST_EDGE_STRENGTH)
		WorldDefClass.CLIMATE_FROZEN:
			fill = fill.lerp(DesignTokens.CLIMATE_FREEZE_TINT, DesignTokens.CLIMATE_FREEZE_FILL_STRENGTH)
			edge = edge.lerp(DesignTokens.CLIMATE_FREEZE_TINT, DesignTokens.CLIMATE_FREEZE_EDGE_STRENGTH)
		_:
			pass
	return [fill, edge]

func _paint_diamond(img: Image, x_off: int, y_off: int, tw: int, th: int, fill: Color, edge: Color) -> void:
	var hx := float(tw) * 0.5
	var hy := float(th) * 0.5
	for py in th:
		for px in tw:
			var dx: float = abs(float(px) + 0.5 - hx) / hx
			var dy: float = abs(float(py) + 0.5 - hy) / hy
			var sum := dx + dy
			if sum <= 1.0:
				if sum >= 0.92:
					img.set_pixel(x_off + px, y_off + py, edge)
				else:
					img.set_pixel(x_off + px, y_off + py, fill)

func _paint_floor_from_world(def: Dictionary) -> void:
	if _tile_layer == null:
		return
	_tile_layer.clear()
	var tiles: Array = def.get("tiles", [])
	for ty in tiles.size():
		var row: Array = tiles[ty]
		for tx in row.size():
			var cell: Dictionary = row[tx]
			var atlas_coord: Vector2i = _atlas_coord_for(String(cell.get("biome", "grass")), String(cell.get("climate", "temperate")))
			_tile_layer.set_cell(Vector2i(tx, ty), SOURCE_ID, atlas_coord)

func _atlas_coord_for(biome: String, climate: String) -> Vector2i:
	var bx: int = max(0, BIOMES_IN_ORDER.find(biome))
	var cy: int = max(0, CLIMATES_IN_ORDER.find(climate))
	return Vector2i(bx, cy)

# ── AStarGrid2D ──────────────────────────────────────────────────────────
func rebuild_astar_from_world() -> void:
	# Public re-entry point used on run restart, after every placeable
	# and resource node has been queue_freed. Replays the initial
	# blocking pattern (lodge core + water tiles) on a fresh grid using
	# the current world def.
	if not world_def.is_empty():
		_build_astar_from_world(world_def)

func _build_astar_from_world(def: Dictionary) -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, Sectors.TILE_GRID_SIZE)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	# Block the lodge core itself.
	astar.set_point_solid(Sectors.LODGE_TILE, true)
	# Block water tiles from the world def — they're terrain obstacles
	# by definition. Resource-node blocking happens later, when the
	# resource node Node2D is placed (it calls block_tile() itself).
	var tiles: Array = def.get("tiles", [])
	for ty in tiles.size():
		var row: Array = tiles[ty]
		for tx in row.size():
			var cell: Dictionary = row[tx]
			if WorldDefClass.is_blocking_biome(String(cell.get("biome", ""))):
				astar.set_point_solid(Vector2i(tx, ty), true)
