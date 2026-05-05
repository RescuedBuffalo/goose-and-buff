extends Node2D
##
## Production node adapter — tile-locked. Coin generation is owned by the
## Economy logic module; this adapter only renders.
##
## Tier dots beneath the icon match the original prototype: each upgrade
## play of the Production Node card bumps the tier and adds a dot.

@export var tier: int = 1

var current_tile: Vector2i = Vector2i.ZERO

func place_at_tile(tile: Vector2i, sector: Node) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)

func set_tier(new_tier: int) -> void:
	tier = new_tier
	queue_redraw()

func _ready() -> void:
	add_to_group("buildings")
	y_sort_enabled = true
	queue_redraw()

func _draw() -> void:
	var faction: String = GameState.hero_id
	var size := Vector2(40, 44)
	var rect := Rect2(-size * 0.5 + Vector2(0, -size.y * 0.5), size)
	draw_rect(rect, DesignTokens.core_color(faction), true)
	draw_rect(rect, DesignTokens.ink_color(faction), false, 2.0)
	# Coin pip — visual cue for "this generates coin".
	draw_circle(Vector2(0, -size.y * 0.5), 9.0, DesignTokens.GOLD_COIN)
	# Tier dots under the icon.
	for i in tier:
		var x := -8.0 + i * 8.0
		draw_circle(Vector2(x, 6.0), 2.5, DesignTokens.GOLD_COIN)
