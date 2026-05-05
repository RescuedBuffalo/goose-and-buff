extends Node2D
##
## Hero adapter — tile-locked Buffalo (and Goose / Fox once they land in
## Phase 2). Click anywhere walkable to walk there; pathfinding runs on the
## sector's AStarGrid2D. The original top-down hero used WASD + free-form
## position; the tile rebuild swaps that for a tile cursor + path queue.
##
## The sector reference is set by main.gd via attach_sector() before _ready
## fires — without it the hero can't translate between tiles and pixels.

const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")

# Pixels-per-stud baseline from the top-down prototype. Hero moveSpeed is
# stored in studs in heroes.gd; the conversion to pixels lets us reuse the
# same number to compute tile traversal time.
const PIXELS_PER_STUD := 12.0
# Distance between adjacent isometric tile centers in screen pixels — used
# as the "step" the move-speed budget pays per tile. Cardinal neighbors at
# 64x32 tiles are sqrt(32^2 + 16^2) ≈ 35.78 px apart; we round to 35 for
# slightly snappier movement that's still inside the original feel envelope.
const TILE_STEP_PX := 35.0

signal hero_downed()
signal tile_changed(new_tile: Vector2i)

var hero_data: Dictionary = Heroes.Buffalo
var hp_max: float = 0.0
var hp: float = 0.0
var is_downed: bool = false
var move_pixels_per_second: float = 0.0
var current_tile: Vector2i = Sectors.SPAWN_TILE
# Path is the queue of remaining tiles to visit; the head is the next tile
# the hero is currently moving toward (via tween). When the tween completes,
# current_tile advances and the next tile pops.
var _path: Array = []
var _moving: bool = false
var _scripted_motion: bool = false

# Sector reference is supplied by main via attach_sector() before add_child;
# leaving it as a plain `var` lets that early assignment survive _ready.
# `@onready` would re-assign null at ready time and break tile→world lookups.
var sector: Node = null
@onready var sprite: Sprite2D = $Sprite

const TOTEM_PATHS := {
	"Buffalo": "res://assets/totems/buffalo.png",
	"Goose": "res://assets/totems/goose.svg",
	"Fox": "res://assets/totems/fox.svg",
}

const TOTEM_SCALE := {
	"Buffalo": Vector2(0.30, 0.30),
	"Goose": Vector2(0.40, 0.40),
	"Fox": Vector2(0.40, 0.40),
}

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func set_hero(hero_id: String) -> void:
	hero_data = Heroes.ALL.get(hero_id, Heroes.Buffalo)

func _ready() -> void:
	hp_max = float(hero_data.baseHealth)
	hp = hp_max
	move_pixels_per_second = float(hero_data.moveSpeed) * PIXELS_PER_STUD
	GameState.set_hero_hp(hp, hp_max)
	add_to_group("hero")
	# Sprite stacks on the y-sort layer above tiles so it never sits behind
	# the floor it's standing on.
	y_sort_enabled = true
	if sprite != null:
		sprite.y_sort_enabled = true
	_load_sprite()
	if sector != null:
		current_tile = Sectors.SPAWN_TILE
		position = sector.tile_to_world(current_tile)

# ── Public API ────────────────────────────────────────────────────────────
func walk_to(target_tile: Vector2i) -> void:
	# Click-to-move entry. Cancels any in-flight tween and replans from the
	# tile we're standing on right now.
	if sector == null or is_downed or _scripted_motion:
		return
	if not sector.is_tile_walkable(target_tile):
		return
	if target_tile == current_tile:
		return
	_path = sector.find_path(current_tile, target_tile)
	_advance()

func reset_position() -> void:
	# Snap back to spawn — called on _start_run / debrief reset.
	_path = []
	_moving = false
	_scripted_motion = false
	current_tile = Sectors.SPAWN_TILE
	if sector != null:
		position = sector.tile_to_world(current_tile)
	tile_changed.emit(current_tile)

func reset_hp() -> void:
	is_downed = false
	hp = hp_max
	if sprite != null:
		sprite.modulate = Color(1, 1, 1, 1)
	GameState.set_hero_hp(hp, hp_max)
	queue_redraw()

func revive() -> void:
	reset_hp()

func damage(amount: float) -> void:
	if is_downed:
		return
	hp = max(0.0, hp - amount)
	GameState.set_hero_hp(hp, hp_max)
	if hp <= 0.0:
		is_downed = true
		if sprite != null:
			sprite.modulate = Color(1.0, 0.3, 0.3, 0.65)
		hero_downed.emit()
	queue_redraw()

func set_scripted_motion(active: bool) -> void:
	_scripted_motion = active

func spawn_tile() -> Vector2i:
	return Sectors.SPAWN_TILE

# ── Movement plumbing ─────────────────────────────────────────────────────
func _advance() -> void:
	if _moving or _path.is_empty() or sector == null:
		return
	if is_downed or _scripted_motion:
		_path = []
		return
	var next_tile: Vector2i = _path.pop_front()
	if not sector.is_tile_walkable(next_tile):
		# Path was invalidated by a building drop / new obstacle. Stop and
		# wait for the next click.
		_path = []
		return
	_moving = true
	# Explicit types needed because `sector` is typed `Node` (the adapter
	# doesn't have a base class to dot into) — type inference can't see the
	# returned Vector2 / float through the dynamic call.
	var target_world: Vector2 = sector.tile_to_world(next_tile)
	var step_seconds: float = TILE_STEP_PX / max(move_pixels_per_second, 1.0)
	var t := create_tween()
	t.tween_property(self, "position", target_world, step_seconds) \
		.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func(): _on_step_complete(next_tile))

func _on_step_complete(arrived_tile: Vector2i) -> void:
	current_tile = arrived_tile
	tile_changed.emit(current_tile)
	_moving = false
	if not _path.is_empty():
		_advance()

# ── Sprite ────────────────────────────────────────────────────────────────
func _load_sprite() -> void:
	var path: String = TOTEM_PATHS.get(hero_data.id, TOTEM_PATHS.Buffalo)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if sprite == null:
		return
	if tex != null:
		sprite.texture = tex
		sprite.scale = TOTEM_SCALE.get(hero_data.id, Vector2(0.35, 0.35))
		# Center the placeholder portrait on the tile. The earlier (0, -28)
		# lift made the sprite render above the tile center, which broke
		# click-to-move intuition — clicks were resolving to the tile under
		# the sprite's body, not the tile under its feet.
		sprite.position = Vector2.ZERO
	else:
		sprite.texture = null
		queue_redraw()

func _draw() -> void:
	if sprite != null and sprite.texture != null and not is_downed:
		return
	var fill: Color = Color(0.5, 0.1, 0.1) if is_downed else DesignTokens.core_color(hero_data.id)
	draw_circle(Vector2.ZERO, 18.0, fill)
	if is_downed:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color(1, 0.1, 0.1, 0.9), 3.0)
		draw_line(Vector2(-10, 0), Vector2(10, -20), Color(1, 0.1, 0.1, 0.9), 3.0)
