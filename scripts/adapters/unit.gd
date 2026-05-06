extends Node2D
##
## Unit adapter — tile-locked deployed AI. Holds formation behind the leader
## (hero) and only breaks off to engage when an enemy enters its detection
## range. Stats from data/units.gd; pathfinding via the sector's AStarGrid2D.

const Sectors := preload("res://data/sectors.gd")

const PIXELS_PER_STUD := 12.0
const TILE_STEP_PX := 35.0

# Detection bubble — units only chase enemies inside this radius. Outside,
# they hold formation. Ranged units get a bigger bubble (their attack range
# would otherwise outpace it). Tile-converted at runtime.
const BASE_DETECTION_TILES := 6
# When the leader runs further than this, the unit drops any engaged target
# and chases the leader. Equivalent of the original prototype's leash.
const LEASH_TILES := 9

@export var unit_id: String = "Calf"

var unit_data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var move_pixels_per_second: float = 0.0
var attack_interval: float = 0.0
var damage_amount: float = 0.0
var attack_range_tiles: int = 1
var detection_tiles: int = BASE_DETECTION_TILES

var current_tile: Vector2i = Vector2i.ZERO
var leader: Node = null  # the hero
var formation_offset: Vector2i = Vector2i.ZERO
var sector: Node = null

var _attack_cooldown: float = 0.0
var _moving: bool = false
var _scripted_motion: bool = false
var _engaged_enemy: Node2D = null

func configure(id: String) -> void:
	unit_id = id

func bind_leader(hero_node: Node, offset: Vector2i) -> void:
	leader = hero_node
	formation_offset = offset

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func place_at_tile(tile: Vector2i) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)

func set_scripted_motion(active: bool) -> void:
	_scripted_motion = active

func _ready() -> void:
	unit_data = UnitsData.ALL[unit_id]
	hp_max = float(unit_data.health)
	hp = hp_max
	move_pixels_per_second = float(unit_data.moveSpeed) * PIXELS_PER_STUD
	attack_interval = float(unit_data.attackInterval)
	damage_amount = float(unit_data.damage)
	# attackRange in unit data is in studs; convert to tiles via 12 px/stud
	# divided by ~32 px/tile-cardinal-step. Cap at 1 so light melee always
	# has at least 1-tile reach.
	var attack_px: float = float(unit_data.attackRange) * PIXELS_PER_STUD
	attack_range_tiles = max(1, int(round(attack_px / TILE_STEP_PX)))
	detection_tiles = max(BASE_DETECTION_TILES, attack_range_tiles + 2)
	add_to_group("units")
	y_sort_enabled = true
	queue_redraw()

func damage(amount: float) -> void:
	# Re-entry guard — same rationale as enemy.damage().
	if hp <= 0.0:
		return
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		queue_free()

func _physics_process(delta: float) -> void:
	if hp <= 0.0 or _scripted_motion or sector == null:
		return
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if _moving:
		# Don't replan mid-step — the tween is in flight. Decisions resume
		# on the next tile.
		return
	# Disengage rules: explicit retreat OR leash distance from leader.
	var leader_far := false
	if leader != null and is_instance_valid(leader):
		var leader_tile: Vector2i = leader.current_tile
		leader_far = sector.tile_distance(current_tile, leader_tile) > LEASH_TILES
	var following_only: bool = GameState.retreat_mode or leader_far
	if not following_only:
		_engaged_enemy = _find_enemy_in_detection()
		if _engaged_enemy != null and is_instance_valid(_engaged_enemy):
			var enemy_tile: Vector2i = _engaged_enemy.current_tile
			var dist: int = sector.tile_distance(current_tile, enemy_tile)
			if dist > attack_range_tiles:
				_step_toward(enemy_tile)
			elif _attack_cooldown <= 0.0:
				_attack_cooldown = attack_interval
				_engaged_enemy.damage(damage_amount)
			return
	# No engage — tail the leader.
	if leader != null and is_instance_valid(leader):
		var anchor: Vector2i = sector.clamp_tile(leader.current_tile + formation_offset)
		if anchor != current_tile and sector.is_tile_walkable(anchor):
			_step_toward(anchor)

func _step_toward(goal_tile: Vector2i) -> void:
	var path: Array = sector.find_path(current_tile, goal_tile)
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	if not sector.is_tile_walkable(next_tile):
		return
	_begin_step(next_tile)

func _begin_step(next_tile: Vector2i) -> void:
	_moving = true
	var target_world: Vector2 = sector.tile_to_world(next_tile)
	var step_seconds: float = TILE_STEP_PX / max(move_pixels_per_second, 1.0)
	var t := create_tween()
	t.tween_property(self, "position", target_world, step_seconds) \
		.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func(): _on_step_complete(next_tile))

func _on_step_complete(arrived: Vector2i) -> void:
	current_tile = arrived
	_moving = false

func _find_enemy_in_detection() -> Node2D:
	var best: Node2D = null
	var best_d := detection_tiles + 1
	for n in get_tree().get_nodes_in_group("enemies"):
		var enemy := n as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_tile: Vector2i = enemy.current_tile
		var d: int = sector.tile_distance(current_tile, enemy_tile)
		if d < best_d:
			best_d = d
			best = enemy
	return best

# ── Drawing ──────────────────────────────────────────────────────────────
func _draw() -> void:
	var fill := _fill_for_unit()
	var size := _size_for_archetype()
	var rect := Rect2(-size * 0.5 + Vector2(0, -size.y * 0.5), size)
	draw_rect(rect, fill, true)
	draw_rect(rect, DesignTokens.ink_color(unit_data.faction), false, 2.0)
	# HP pip above.
	var hp_ratio: float = 0.0 if hp_max == 0 else hp / hp_max
	var bar_w := size.x
	var bar_y := -size.y - 6.0
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, 3.0), DesignTokens.hp_color(hp_ratio), true)

func _fill_for_unit() -> Color:
	var floor_c: Color = DesignTokens.floor_color(unit_data.faction)
	var core_c: Color = DesignTokens.core_color(unit_data.faction)
	match unit_data.archetype:
		"light": return floor_c
		"ranged": return floor_c.lerp(core_c, 0.5)
		"heavy": return core_c
		_: return floor_c

func _size_for_archetype() -> Vector2:
	match unit_data.archetype:
		"light": return Vector2(20, 22)
		"ranged": return Vector2(20, 26)
		"heavy": return Vector2(28, 30)
		_: return Vector2(20, 22)
