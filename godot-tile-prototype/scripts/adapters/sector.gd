extends Node2D
##
## Sector adapter — owns the TileMapLayer, the placeholder TileSet, and the
## AStarGrid2D pathfinding graph. The original top-down sector drew a flat
## floor with _draw(); the tile rebuild paints diamonds on a real tile grid
## and exposes tile<->world conversion + path lookup.
##
## All consumers (hero, units, enemies, hand drop targeting) go through the
## helpers here — they should never reach into _tile_layer directly. The
## sector is the only adapter that knows the projection.
##
## Pure-data tile coords come from data/sectors.gd. The atlas / TileSet
## painting is procedural so the prototype runs without any imported tile
## artwork — image textures are built in code at sector ready.

const Sectors := preload("res://data/sectors.gd")

signal core_destroyed()
signal core_hp_changed(current: float, maximum: float)

# Atlas tile types. Each entry is the (column, row) in the procedurally-built
# TileSet atlas — see _build_atlas_texture.
const ATLAS_FLOOR := Vector2i(0, 0)
const ATLAS_CORE := Vector2i(1, 0)
const ATLAS_SPAWN := Vector2i(2, 0)
const ATLAS_ENTRY := Vector2i(3, 0)

# Source id we use when adding the atlas to the TileSet. Arbitrary.
const SOURCE_ID := 0

var hero_id: String = "Buffalo"
var core_hp: float = Sectors.CORE_HEALTH
var core_hp_max: float = Sectors.CORE_HEALTH
var astar: AStarGrid2D
var _tile_layer: TileMapLayer
var _deploy_highlight: bool = false

func _ready() -> void:
	add_to_group("sector")
	# Anchor the tile origin at the sector's world offset. The TileMapLayer
	# computes (0, 0)..(N, M) tile centers relative to its node position.
	position = Sectors.WORLD_OFFSET
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
	# Repaint the floor in the new faction palette. M4 swaps the whole tileset
	# rather than re-coloring per cell — the atlas is small enough that a
	# rebuild is cheaper than caching N variants. Only used in solo retoning.
	if hero_id == new_hero_id:
		return
	hero_id = new_hero_id
	if _tile_layer != null:
		_tile_layer.tile_set = _build_tile_set(hero_id)
		_paint_floor()
	queue_redraw()

# ── Tile coordinate API ───────────────────────────────────────────────────
func tile_to_world(tile: Vector2i) -> Vector2:
	# Tile center in global viewport coords. Adapters never reach into the
	# TileMapLayer directly — they call this to position sprites.
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

# ── Pathfinding ───────────────────────────────────────────────────────────
func find_path(from_tile: Vector2i, to_tile: Vector2i) -> Array:
	# Returns the tile-space path from from_tile to to_tile, with the start
	# node dropped so callers can iterate "next tile to step toward".
	# If the goal is solid (e.g. enemies pathing to the core), the call
	# falls back to the closest reachable adjacent tile so wave AI doesn't
	# stall at the gates.
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
	# get_id_path returns Array[Vector2i]; let the inference catch it instead
	# of forcing an untyped Array assignment which Godot can warn about.
	var raw := astar.get_id_path(from_tile, goal)
	if raw.size() <= 1:
		return []
	# Strip the start so each call returns "everything left to walk".
	var stripped: Array = []
	for i in range(1, raw.size()):
		stripped.append(raw[i])
	return stripped

func tile_distance(a: Vector2i, b: Vector2i) -> int:
	# Chebyshev distance — diagonal-mode-NEVER paths only step cardinally,
	# so the tile-step count between two tiles is the Manhattan distance.
	return abs(a.x - b.x) + abs(a.y - b.y)

func _nearest_walkable_neighbor(target: Vector2i, from_tile: Vector2i) -> Vector2i:
	# Pick the cardinal neighbor of `target` that's walkable AND closest to
	# `from_tile` — this is what enemies use when their goal is the core.
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
	# Restore both current AND max — main._start_run calls GameState.reset()
	# which zeros core_hp_max, so just rewriting core_hp here would leave the
	# HUD reading "1000 / 0" with a 0/0 ratio that pegs the bar to crit color.
	core_hp = core_hp_max
	GameState.core_hp = core_hp
	GameState.core_hp_max = core_hp_max
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()

# ── Visuals ───────────────────────────────────────────────────────────────
func set_deploy_highlight(active: bool) -> void:
	if _deploy_highlight == active:
		return
	_deploy_highlight = active
	queue_redraw()

func _draw() -> void:
	# Core HP bar above the core tile. The TileMapLayer paints the cells; this
	# overlay sits in the sector's own canvas item so HP changes don't force
	# a tile repaint.
	var core_world := _tile_layer.map_to_local(Sectors.CORE_TILE)
	var bar_w := 80.0
	var bar_h := 4.0
	var bar_x := core_world.x - bar_w * 0.5
	var bar_y := core_world.y - 24.0
	var hp_ratio: float = 0.0 if core_hp_max == 0 else core_hp / core_hp_max
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, bar_h), DesignTokens.hp_color(hp_ratio), true)
	if _deploy_highlight:
		# Thin diamond outlines on every walkable tile — reads as "drop here
		# is legal" without overwhelming the floor underneath.
		var accent := DesignTokens.core_color(hero_id)
		var border := Color(accent.r, accent.g, accent.b, 0.55)
		for tile in Sectors.all_floor_tiles():
			if tile == Sectors.CORE_TILE:
				continue
			_draw_diamond_outline(_tile_layer.map_to_local(tile), border, 2.0)

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
	atlas.create_tile(ATLAS_FLOOR)
	atlas.create_tile(ATLAS_CORE)
	atlas.create_tile(ATLAS_SPAWN)
	atlas.create_tile(ATLAS_ENTRY)
	ts.add_source(atlas, SOURCE_ID)
	return ts

func _build_atlas_texture(hero: String) -> Texture2D:
	var tw: int = Sectors.TILE_PIXELS.x
	var th: int = Sectors.TILE_PIXELS.y
	# Atlas is one row of four tiles: floor, core, spawn, entry.
	var img := Image.create(tw * 4, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var floor_c: Color = DesignTokens.floor_color(hero)
	var floor_edge: Color = DesignTokens.ink_color(hero)
	var core_c: Color = DesignTokens.core_color(hero)
	var core_edge: Color = DesignTokens.NIGHT_0
	var spawn_c: Color = DesignTokens.PARCHMENT_2
	var entry_base: Color = DesignTokens.HP_CRIT
	var entry_c := Color(entry_base.r, entry_base.g, entry_base.b, 0.55)
	_paint_diamond(img, 0, tw, th, floor_c, floor_edge)
	_paint_diamond(img, tw, tw, th, core_c, core_edge)
	_paint_diamond(img, tw * 2, tw, th, spawn_c, floor_edge)
	_paint_diamond(img, tw * 3, tw, th, entry_c, core_edge)
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
		var atlas_coord: Vector2i = ATLAS_FLOOR
		if tile == Sectors.CORE_TILE:
			atlas_coord = ATLAS_CORE
		elif tile == Sectors.SPAWN_TILE:
			atlas_coord = ATLAS_SPAWN
		elif Sectors.ENEMY_ENTRY_TILES.has(tile):
			atlas_coord = ATLAS_ENTRY
		_tile_layer.set_cell(tile, SOURCE_ID, atlas_coord)

# ── AStarGrid2D ──────────────────────────────────────────────────────────
func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, Sectors.TILE_GRID_SIZE)
	astar.cell_size = Vector2(1, 1)
	# Cardinal-only paths keep enemy lines reading clean. Diagonal mode is
	# easy to flip to AT_LEAST_ONE_WALKABLE later if movement feels too rigid.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	# Block the core tile so units / enemies path around it. Adjacency is
	# what triggers core damage — the goal of "reach the core" resolves to a
	# neighbor via _nearest_walkable_neighbor.
	astar.set_point_solid(Sectors.CORE_TILE, true)
