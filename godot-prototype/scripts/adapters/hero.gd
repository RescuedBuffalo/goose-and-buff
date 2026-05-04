extends Node2D
##
## Buffalo character. WASD movement, clamped to the sector. Stat values
## come from data/heroes.gd; the totem PNG is the placeholder sprite.

const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")

const PIXELS_PER_STUD := 12.0  # roughly maps Roblox moveSpeed to pixels/s

var hero_data: Dictionary = Heroes.Buffalo
var hp_max: float = 0.0
var hp: float = 0.0
var move_pixels_per_second: float = 0.0

@onready var sprite: Sprite2D = $Sprite

func _ready() -> void:
	hp_max = float(hero_data.baseHealth)
	hp = hp_max
	move_pixels_per_second = float(hero_data.moveSpeed) * PIXELS_PER_STUD
	GameState.set_hero_hp(hp, hp_max)
	position = Sectors.SPAWN_PAD_CENTER + Vector2(60, 0)
	_load_sprite()

func _physics_process(delta: float) -> void:
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
	hp = max(0.0, hp - amount)
	GameState.set_hero_hp(hp, hp_max)

func reset_hp() -> void:
	# Re-applies hero HP to GameState. Called from main._start_run after
	# GameState.reset() so the HUD reads the right values on first frame.
	hp = hp_max
	GameState.set_hero_hp(hp, hp_max)

func _load_sprite() -> void:
	# The shipped buffalo asset is a PNG. The other totems are SVG; Godot
	# imports both natively. Sprite is scaled down from the source 240×200.
	var tex: Texture2D = load("res://assets/totems/buffalo.png")
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(0.45, 0.45)
		sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Fallback: a flat parchment circle so the hero is still visible.
		sprite.texture = null
		queue_redraw()

func _draw() -> void:
	if sprite.texture == null:
		draw_circle(Vector2.ZERO, 24.0, DesignTokens.BUFFALO_CORE)
