extends Node2D
##
## A placed building. v0 only ships Production Node — the visual is just a
## tinted square with a tier number. The economy module owns the actual
## coin generation; this adapter only renders.

@export var tier: int = 1

func set_tier(new_tier: int) -> void:
	tier = new_tier
	queue_redraw()

func _ready() -> void:
	add_to_group("buildings")
	queue_redraw()

func _draw() -> void:
	var size := Vector2(56, 56)
	var rect := Rect2(-size * 0.5, size)
	# Production node retones with the active hero so a Fox sector doesn't
	# get a Buffalo-brown building grafted onto its peach floor.
	draw_rect(rect, DesignTokens.core_color(GameState.hero_id), true)
	draw_rect(rect, DesignTokens.ink_color(GameState.hero_id), false, 2.0)
	# Inner gold pip — the coin source.
	draw_circle(Vector2.ZERO, 12.0, DesignTokens.GOLD_COIN)
	# Tier dots beneath.
	var dot_y := size.y * 0.5 + 6.0
	for i in tier:
		var x := -8.0 + i * 8.0
		draw_circle(Vector2(x, dot_y), 2.5, DesignTokens.GOLD_COIN)
