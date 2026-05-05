extends Node2D
##
## The player character. Identity (Goose / Buffalo / Fox) is set by
## main.gd before the scene enters the tree via `set_hero(hero_id)`.
## WASD movement, clamped to the sector. Stat values come from
## data/heroes.gd; the totem image is the placeholder sprite.

const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")

const PIXELS_PER_STUD := 12.0  # roughly maps Roblox moveSpeed to pixels/s

# Per-hero totem assets. Buffalo is a PNG; Goose / Fox are SVG. Both load
# through Texture2D so the rest of the file doesn't care.
const TOTEM_PATHS := {
	"Buffalo": "res://assets/totems/buffalo.png",
	"Goose": "res://assets/totems/goose.svg",
	"Fox": "res://assets/totems/fox.svg",
}

# Each totem source has a different native resolution; tune the scale so the
# rendered size matches across heroes (Buffalo's PNG is ~240x200, the SVGs
# import at ~96px square).
const TOTEM_SCALE := {
	"Buffalo": Vector2(0.45, 0.45),
	"Goose": Vector2(0.65, 0.65),
	"Fox": Vector2(0.65, 0.65),
}

signal hero_downed

var hero_data: Dictionary = Heroes.Buffalo
var hp_max: float = 0.0
var hp: float = 0.0
var is_downed: bool = false
var move_pixels_per_second: float = 0.0
var _scripted_motion: bool = false  # disables input while a tween moves us

const SPAWN_OFFSET := Vector2(60, 0)

@onready var sprite: Sprite2D = $Sprite

func set_hero(hero_id: String) -> void:
	# Call before the node enters the tree; _ready() picks up the new dict.
	# Falls back to Buffalo on an unknown id rather than crashing — the
	# select screen only ever sends a canonical id, so a fallback here is
	# defensive, not load-bearing.
	hero_data = Heroes.ALL.get(hero_id, Heroes.Buffalo)

func _ready() -> void:
	hp_max = float(hero_data.baseHealth)
	hp = hp_max
	move_pixels_per_second = float(hero_data.moveSpeed) * PIXELS_PER_STUD
	GameState.set_hero_hp(hp, hp_max)
	position = spawn_position()
	add_to_group("hero")
	_load_sprite()

func spawn_position() -> Vector2:
	return Sectors.SPAWN_PAD_CENTER + SPAWN_OFFSET

func set_scripted_motion(active: bool) -> void:
	_scripted_motion = active

func _physics_process(delta: float) -> void:
	if _scripted_motion or is_downed:
		return
	var dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
		var next := position + dir * move_pixels_per_second * delta
		next.x = clamp(next.x, Sectors.SECTOR_LEFT + 32, Sectors.SECTOR_RIGHT - 32)
		next.y = clamp(next.y, Sectors.SECTOR_TOP + 32, Sectors.SECTOR_BOTTOM - 32)
		position = next

func damage(amount: float) -> void:
	if is_downed:
		return
	hp = max(0.0, hp - amount)
	GameState.set_hero_hp(hp, hp_max)
	if hp <= 0.0:
		is_downed = true
		sprite.modulate = Color(1.0, 0.3, 0.3, 0.65)
		hero_downed.emit()
		queue_redraw()

func revive() -> void:
	# Clears downed state and restores full HP. Called after each wave victory
	# so a downed hero is back to full when the next round's prep begins.
	is_downed = false
	hp = hp_max
	sprite.modulate = Color(1, 1, 1, 1)
	GameState.set_hero_hp(hp, hp_max)
	queue_redraw()

func reset_hp() -> void:
	# Re-applies hero HP to GameState. Called from main._start_run after
	# GameState.reset() so the HUD reads the right values on first frame.
	is_downed = false
	hp = hp_max
	sprite.modulate = Color(1, 1, 1, 1)
	GameState.set_hero_hp(hp, hp_max)
	queue_redraw()

func reset_position() -> void:
	# Snap the hero back to the spawn pad. Called by main._start_run on a
	# fresh run / restart so each opening is identical regardless of where
	# the player was standing when the previous run ended.
	_scripted_motion = false
	position = spawn_position()

func _load_sprite() -> void:
	var path: String = TOTEM_PATHS.get(hero_data.id, TOTEM_PATHS.Buffalo)
	var tex: Texture2D = load(path)
	if tex:
		sprite.texture = tex
		sprite.scale = TOTEM_SCALE.get(hero_data.id, Vector2(0.5, 0.5))
		sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Fallback: a flat parchment circle in the hero's core color so the
		# character stays visible even if asset import is mid-flight.
		sprite.texture = null
		queue_redraw()

func _draw() -> void:
	if sprite.texture == null:
		var fill := Color(0.5, 0.1, 0.1) if is_downed else DesignTokens.core_color(hero_data.id)
		draw_circle(Vector2.ZERO, 24.0, fill)
	if is_downed:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color(1, 0.1, 0.1, 0.9), 3.0)
		draw_line(Vector2(-10, 10), Vector2(10, -10), Color(1, 0.1, 0.1, 0.9), 3.0)
