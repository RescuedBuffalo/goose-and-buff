extends Node2D
##
## Hero adapter — WASD-controlled Buffalo with cursor-facing for the
## survival rebuild. The wave-defense build click-to-moved on the tile
## grid; survival reframes the hero as a walking presence in the world,
## so input switches to direction-of-press movement and click is reserved
## for combat swing.
##
## Movement is pixel-grain (smooth diagonal feel, free-form motion) but
## current_tile is updated each frame from the rounded position so the
## tile-aware systems (gather, build, enemy targeting) keep their
## tile-grain contract.

const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")

const PIXELS_PER_STUD := 12.0

signal hero_downed()
signal tile_changed(new_tile: Vector2i)
signal facing_changed(new_facing: Vector2)

var hero_data: Dictionary = Heroes.Buffalo
var hp_max: float = 0.0
var hp: float = 0.0
var is_downed: bool = false
var move_pixels_per_second: float = 0.0
var current_tile: Vector2i = Sectors.SPAWN_TILE
var facing: Vector2 = Vector2.RIGHT

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
	y_sort_enabled = true
	if sprite != null:
		sprite.y_sort_enabled = true
	_load_sprite()
	if sector != null:
		current_tile = Sectors.SPAWN_TILE
		position = sector.tile_to_world(current_tile)

func _physics_process(delta: float) -> void:
	if is_downed or sector == null:
		return
	# Freeze movement + facing once the run ends. main.gd's _process
	# already gates the cycle/wave/combat ticks on this; mirror it here
	# so the hero doesn't drift behind the end-screen scrim.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	# WASD → direct screen-cardinal movement. The Hades / Stardew
	# convention: pressing "up" walks the hero straight up on the
	# screen, regardless of how the iso tile axes are oriented. Tile
	# coords update as a side-effect when the hero crosses boundaries.
	var input_dir: Vector2 = _read_input_direction()
	if input_dir != Vector2.ZERO:
		var step: Vector2 = input_dir * move_pixels_per_second * delta
		var proposed: Vector2 = position + step
		var proposed_tile: Vector2i = sector.world_to_tile(proposed)
		if sector.is_tile_walkable(proposed_tile):
			position = proposed
		else:
			# Slide along the unblocked axis if any — feels less sticky
			# than a hard stop into corners.
			var dx_only: Vector2 = position + Vector2(step.x, 0)
			var dy_only: Vector2 = position + Vector2(0, step.y)
			if sector.is_tile_walkable(sector.world_to_tile(dx_only)):
				position = dx_only
			elif sector.is_tile_walkable(sector.world_to_tile(dy_only)):
				position = dy_only
		var new_tile: Vector2i = sector.world_to_tile(position)
		if new_tile != current_tile:
			current_tile = new_tile
			tile_changed.emit(current_tile)
	# Face toward cursor every frame so the swing arc reads honestly.
	# Falling back to last facing if the cursor is somehow on top of us.
	var mouse_world: Vector2 = get_global_mouse_position()
	var to_cursor: Vector2 = mouse_world - position
	if to_cursor.length_squared() > 4.0:
		var new_facing: Vector2 = to_cursor.normalized()
		if new_facing != facing:
			facing = new_facing
			facing_changed.emit(facing)

func reset_position() -> void:
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

func spawn_tile() -> Vector2i:
	return Sectors.SPAWN_TILE

# ── Input ────────────────────────────────────────────────────────────

func _read_input_direction() -> Vector2:
	# Action names are registered in project.godot (move_up/down/left/right).
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	return dir

# ── Sprite ───────────────────────────────────────────────────────────

func _load_sprite() -> void:
	var path: String = TOTEM_PATHS.get(hero_data.id, TOTEM_PATHS.Buffalo)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if sprite == null:
		return
	if tex != null:
		sprite.texture = tex
		sprite.scale = TOTEM_SCALE.get(hero_data.id, Vector2(0.35, 0.35))
		sprite.position = Vector2.ZERO
	else:
		sprite.texture = null
		queue_redraw()

func _draw() -> void:
	# When no totem texture is available the hero is a colored disc
	# with a small forward-facing notch so the player can see which way
	# the swing arc will fire.
	if sprite != null and sprite.texture != null and not is_downed:
		_draw_facing_notch()
		return
	var fill: Color = Color(0.5, 0.1, 0.1) if is_downed else DesignTokens.core_color(hero_data.id)
	draw_circle(Vector2.ZERO, 18.0, fill)
	if is_downed:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color(1, 0.1, 0.1, 0.9), 3.0)
		draw_line(Vector2(-10, 0), Vector2(10, -20), Color(1, 0.1, 0.1, 0.9), 3.0)
	else:
		_draw_facing_notch()

func _draw_facing_notch() -> void:
	# Tiny indicator at the hero's feet pointing where they're facing —
	# helps make swing direction legible while sprites are placeholder.
	var tip: Vector2 = facing.normalized() * 22.0
	var perp := Vector2(-facing.y, facing.x).normalized() * 4.0
	var notch_color := Color(DesignTokens.PARCHMENT_0.r, DesignTokens.PARCHMENT_0.g, DesignTokens.PARCHMENT_0.b, 0.85)
	draw_polygon(
		PackedVector2Array([tip, tip - facing * 8.0 + perp, tip - facing * 8.0 - perp]),
		PackedColorArray([notch_color, notch_color, notch_color]),
	)
