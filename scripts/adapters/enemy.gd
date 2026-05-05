extends Node2D
##
## Enemy adapter — tile-locked grunt. Walks toward the core via the sector's
## AStarGrid2D, engages units / hero in attack range. The original top-down
## version used pixel positions and free-form motion; tile rebuild swaps in
## tile pathing + per-tile tweens.
##
## attackRange / coreRange in enemies.gd are pixel values; we convert to
## tiles so the engage check stays tile-grid native.

const Enemies := preload("res://data/enemies.gd")
const Sectors := preload("res://data/sectors.gd")

const TILE_STEP_PX := 35.0
# Pixel-to-tile conversion baseline. The data file mixes "studs * 12" and
# raw px in attack ranges; both end up px after _ready, then we round to
# tiles via this divisor (cardinal isometric step distance).
const PX_PER_TILE := 32.0

@export var enemy_type: String = "GruntMelee"

signal died(self_ref: Node)
signal reached_core(self_ref: Node)

var data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var current_tile: Vector2i = Vector2i.ZERO
var sector: Node = null
var attack_range_tiles: int = 1
var core_range_tiles: int = 1
var preferred_range_tiles: int = 0

var _attack_cooldown: float = 0.0
var _moving: bool = false
var _engaged_target: Node2D = null

func configure(type: String) -> void:
	enemy_type = type

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func place_at_tile(tile: Vector2i) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)

func _ready() -> void:
	data = Enemies.ALL[enemy_type]
	hp_max = float(data.health)
	hp = hp_max
	attack_range_tiles = max(1, int(round(float(data.attackRange) / PX_PER_TILE)))
	core_range_tiles = max(1, int(round(float(data.get("coreRange", data.attackRange)) / PX_PER_TILE)))
	preferred_range_tiles = int(round(float(data.get("preferred_range", 0.0)) / PX_PER_TILE))
	add_to_group("enemies")
	y_sort_enabled = true
	queue_redraw()

func damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		died.emit(self)
		queue_free()

func apply_knockback(direction: Vector2, distance: float) -> void:
	# Tile-snap version of the original knockback. Convert direction + px
	# distance into tile steps; if the resulting tile is walkable, snap there.
	if sector == null:
		return
	var tiles: int = int(round(distance / PX_PER_TILE))
	if tiles <= 0:
		return
	var step: Vector2i
	if abs(direction.x) >= abs(direction.y):
		step = Vector2i(int(sign(direction.x)), 0)
	else:
		step = Vector2i(0, int(sign(direction.y)))
	var target := current_tile
	for i in tiles:
		var probe: Vector2i = target + step
		if not sector.is_tile_walkable(probe):
			break
		target = probe
	if target != current_tile:
		current_tile = target
		# Snap visually — knockback is a hit reaction, not a smooth glide.
		position = sector.tile_to_world(current_tile)

func _physics_process(delta: float) -> void:
	if hp <= 0.0 or sector == null or _moving:
		return
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	# Refresh engagement target once per tile rather than every frame —
	# combat is tile-grain so checking continuously is overkill.
	if _engaged_target == null or not is_instance_valid(_engaged_target):
		_engaged_target = _find_engageable_target()
	# Drop a downed hero so we go back to walking on the core.
	if _engaged_target != null and _engaged_target.get("is_downed"):
		_engaged_target = null
	if _engaged_target != null and is_instance_valid(_engaged_target):
		var t_tile: Vector2i = _engaged_target.current_tile
		var dist: int = sector.tile_distance(current_tile, t_tile)
		if dist <= attack_range_tiles:
			if _attack_cooldown <= 0.0:
				_attack_cooldown = float(data.attackInterval)
				_engaged_target.damage(float(data.damage))
			# Ranged archetypes back away if a target closes inside their
			# preferred range — fragile vs. melee otherwise.
			if data.get("keep_distance", false) and dist < preferred_range_tiles:
				_step_away_from(t_tile)
			return
		_step_toward(t_tile)
		return
	# Default goal: the core. Reaching adjacency is the kill-the-core hit.
	var dist_to_core: int = sector.tile_distance(current_tile, Sectors.CORE_TILE)
	if dist_to_core <= core_range_tiles:
		if _attack_cooldown <= 0.0:
			_attack_cooldown = float(data.attackInterval)
			# Single hit — main listens to reached_core and damages the core,
			# then frees us.
			reached_core.emit(self)
		return
	_step_toward(Sectors.CORE_TILE)

func _step_toward(goal_tile: Vector2i) -> void:
	var path: Array = sector.find_path(current_tile, goal_tile)
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	if not sector.is_tile_walkable(next_tile):
		return
	_begin_step(next_tile)

func _step_away_from(target_tile: Vector2i) -> void:
	var dx: int = current_tile.x - target_tile.x
	var dy: int = current_tile.y - target_tile.y
	var step: Vector2i
	if abs(dx) >= abs(dy):
		step = Vector2i(int(sign(dx)), 0)
	else:
		step = Vector2i(0, int(sign(dy)))
	if step == Vector2i.ZERO:
		return
	var probe: Vector2i = current_tile + step
	if not sector.is_tile_walkable(probe):
		return
	_begin_step(probe)

func _begin_step(next_tile: Vector2i) -> void:
	_moving = true
	var target_world: Vector2 = sector.tile_to_world(next_tile)
	var step_seconds: float = TILE_STEP_PX / max(float(data.moveSpeed), 1.0)
	var t := create_tween()
	t.tween_property(self, "position", target_world, step_seconds) \
		.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func(): _on_step_complete(next_tile))

func _on_step_complete(arrived: Vector2i) -> void:
	current_tile = arrived
	_moving = false

func _find_engageable_target() -> Node2D:
	var best: Node2D = null
	var best_d: int = attack_range_tiles + 1
	# Units first.
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		var d: int = sector.tile_distance(current_tile, u.current_tile)
		if d < best_d:
			best_d = d
			best = u
	# Hero — adjacent-tile damage was flagged as pending in godot-prototype's
	# notes; the tile rebuild wires it through.
	for n in get_tree().get_nodes_in_group("hero"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if h.get("is_downed"):
			continue
		var d: int = sector.tile_distance(current_tile, h.current_tile)
		if d < best_d:
			best_d = d
			best = h
	return best

# ── Drawing ──────────────────────────────────────────────────────────────
func _draw() -> void:
	var size: Vector2 = data.size
	var rect := Rect2(-size * 0.5 + Vector2(0, -size.y * 0.5), size)
	draw_rect(rect, data.color_rgba, true)
	draw_rect(rect, DesignTokens.NIGHT_0, false, 2.0)
	var hp_ratio: float = 0.0 if hp_max == 0 else hp / hp_max
	var bar_y := -size.y - 6.0
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x, 3.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x * hp_ratio, 3.0), DesignTokens.hp_color(hp_ratio), true)
