extends Node2D
##
## Sector adapter — owns the TileMapLayer, the procedurally-built
## TileSet, and the AStarGrid2D pathfinding graph. The survival rebuild
## widens the grid to 25x25 and paints biome tiles (grass, treeline,
## rocks, water, sand) so the world reads as more than a flat arena.
##
## Resource nodes (trees / rocks / bushes) are NOT tiles — they are
## Node2D children placed on top of grass tiles by the world adapter.
## The sector exposes block_tile / unblock_tile so those adapters can
## hook into AStar without reaching across layers.
##
## Tile coords come from data/sectors.gd. The atlas is procedural so the
## prototype runs without imported tile artwork.

const Sectors := preload("res://data/sectors.gd")

signal core_destroyed()
signal core_hp_changed(current: float, maximum: float)

# Atlas coordinates — one row of tiles in the procedural texture.
const ATLAS_GRASS := Vector2i(0, 0)
const ATLAS_LODGE := Vector2i(1, 0)
const ATLAS_ENTRY := Vector2i(2, 0)
const ATLAS_WATER := Vector2i(3, 0)
const ATLAS_SAND := Vector2i(4, 0)
const ATLAS_ROCK := Vector2i(5, 0)
const ATLAS_LEAF := Vector2i(6, 0)

const ATLAS_KEYS := [
	ATLAS_GRASS, ATLAS_LODGE, ATLAS_ENTRY,
	ATLAS_WATER, ATLAS_SAND, ATLAS_ROCK, ATLAS_LEAF,
]

const SOURCE_ID := 0

var hero_id: String = "Buffalo"
var core_hp: float = Sectors.CORE_HEALTH
var core_hp_max: float = Sectors.CORE_HEALTH
var astar: AStarGrid2D
var _tile_layer: TileMapLayer
var _build_highlight_tile: Vector2i = Vector2i(-1, -1)
var _build_highlight_valid: bool = true

func _ready() -> void:
	add_to_group("sector")
	# The world is now larger than the screen — anchor the TileMap at
	# (0,0) and let the camera pan over it, instead of pre-centering.
	position = Vector2.ZERO
	_tile_layer = TileMapLayer.new()
	_tile_layer.tile_set = _build_tile_set(hero_id)
	_tile_layer.y_sort_enabled = true
	add_child(_tile_layer)
	_paint_floor()
	_build_astar()
	GameState.core_hp = core_hp
	GameState.core_hp_max = core_hp_max
	queue_redraw()

# ── Identity ──────────────────────────────────────────────────────────────
func set_hero(new_hero_id: String) -> void:
	if hero_id == new_hero_id:
		return
	hero_id = new_hero_id
	if _tile_layer != null:
		_tile_layer.tile_set = _build_tile_set(hero_id)
		_paint_floor()
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
	GameState.core_hp = core_hp
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()
	if core_hp <= 0.0:
		core_destroyed.emit()

func reset_core() -> void:
	core_hp = core_hp_max
	GameState.core_hp = core_hp
	GameState.core_hp_max = core_hp_max
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
	for k in ATLAS_KEYS:
		atlas.create_tile(k)
	ts.add_source(atlas, SOURCE_ID)
	return ts

func _build_atlas_texture(hero: String) -> Texture2D:
	var tw: int = Sectors.TILE_PIXELS.x
	var th: int = Sectors.TILE_PIXELS.y
	var tile_count: int = ATLAS_KEYS.size()
	var img := Image.create(tw * tile_count, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Color recipes per atlas index — kept warm so the lit-by-lantern
	# palette holds up. Neutral-leaning tones for treeline/rocks so the
	# Buffalo floor still reads as the dominant ground.
	var palette := {
		ATLAS_GRASS: [Color8(94, 110, 76), Color8(60, 70, 48)],
		ATLAS_LODGE: [DesignTokens.core_color(hero), DesignTokens.NIGHT_0],
		ATLAS_ENTRY: [Color(DesignTokens.HP_CRIT.r, DesignTokens.HP_CRIT.g, DesignTokens.HP_CRIT.b, 0.55),
				DesignTokens.NIGHT_0],
		ATLAS_WATER: [Color8(54, 88, 120), Color8(28, 52, 80)],
		ATLAS_SAND:  [Color8(180, 156, 110), Color8(120, 96, 64)],
		ATLAS_ROCK:  [Color8(118, 110, 100), Color8(60, 56, 50)],
		ATLAS_LEAF:  [Color8(72, 96, 64), Color8(40, 56, 40)],
	}
	for i in tile_count:
		var key: Vector2i = ATLAS_KEYS[i]
		var pair = palette.get(key, [DesignTokens.NIGHT_2, DesignTokens.NIGHT_0])
		_paint_diamond(img, i * tw, tw, th, pair[0], pair[1])
	return ImageTexture.create_from_image(img)

func _paint_diamond(img: Image, x_off: int, tw: int, th: int, fill: Color, edge: Color) -> void:
	var hx := float(tw) * 0.5
	var hy := float(th) * 0.5
	for py in th:
		for px in tw:
			var dx: float = abs(float(px) + 0.5 - hx) / hx
			var dy: float = abs(float(py) + 0.5 - hy) / hy
			var sum := dx + dy
			if sum <= 1.0:
				if sum >= 0.92:
					img.set_pixel(x_off + px, py, edge)
				else:
					img.set_pixel(x_off + px, py, fill)

func _paint_floor() -> void:
	_tile_layer.clear()
	for tile in Sectors.all_floor_tiles():
		var atlas_coord: Vector2i = _atlas_for_tile(tile)
		_tile_layer.set_cell(tile, SOURCE_ID, atlas_coord)

func _atlas_for_tile(tile: Vector2i) -> Vector2i:
	# Order: lodge → entry → water → rocks → trees (leaf) → grass.
	# Sand/beach is reserved for adjacency to water.
	if tile == Sectors.LODGE_TILE:
		return ATLAS_LODGE
	if Sectors.ENEMY_ENTRY_TILES.has(tile):
		return ATLAS_ENTRY
	var biome: String = Sectors.biome_at(tile)
	match biome:
		"water": return ATLAS_WATER
		"rocks": return ATLAS_ROCK
		"trees": return ATLAS_LEAF
		"berries": return ATLAS_GRASS  # bushes sit on grass
		"open": return ATLAS_GRASS
		_:
			# Sand band along the water edge for legibility.
			if _is_water_adjacent(tile):
				return ATLAS_SAND
			return ATLAS_GRASS

func _is_water_adjacent(tile: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var probe := Vector2i(tile.x + dx, tile.y + dy)
			if Sectors.biome_at(probe) == "water":
				return true
	return false

# ── AStarGrid2D ──────────────────────────────────────────────────────────
func rebuild_astar() -> void:
	# Public re-entry point used on run restart, after every placeable
	# and resource node has been queue_freed. Replays the initial
	# blocking pattern (lodge core + water tiles) on a fresh grid.
	_build_astar()

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, Sectors.TILE_GRID_SIZE)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	# Block the lodge core itself.
	astar.set_point_solid(Sectors.LODGE_TILE, true)
	# Block water tiles — they're terrain obstacles by definition.
	for tile in Sectors.all_floor_tiles():
		if Sectors.biome_at(tile) == "water":
			astar.set_point_solid(tile, true)
