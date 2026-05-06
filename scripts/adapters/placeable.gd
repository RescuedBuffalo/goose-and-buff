extends Node2D
##
## Placeable adapter — walls, gates, torches, production nodes. Spawned
## by main when BuildSystem.placed fires; the adapter pulls its own
## stats from data/placeables.gd at ready, blocks the AStar tile if the
## placeable is movement-blocking, and renders.
##
## HP is tracked but not yet damaged in MVP — wolves currently path
## around walls but don't attack them. When that lands, this adapter is
## where damage() handlers go.

const Placeables := preload("res://data/placeables.gd")

@export var placeable_id: String = "wood_wall"

var data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var current_tile: Vector2i = Vector2i.ZERO
var sector: Node = null

func configure(id: String) -> void:
	placeable_id = id

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func place_at_tile(tile: Vector2i) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)
		# Block movement here rather than in _ready — _ready fires inside
		# add_child(), before main has had a chance to call place_at_tile,
		# so the tile would otherwise be the default (0, 0).
		if data.get("blocks_movement", false):
			sector.block_tile(current_tile)

func _ready() -> void:
	data = Placeables.get_placeable(placeable_id)
	hp_max = float(data.get("hp", 1.0))
	hp = hp_max
	add_to_group("placeables")
	y_sort_enabled = true
	queue_redraw()

func damage(amount: float) -> void:
	# Re-entry guard — same rationale as enemy.damage(). A wall hit by
	# concurrent damage sources in one frame should only unblock its
	# tile once.
	if hp <= 0.0:
		return
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		if sector != null and data.get("blocks_movement", false):
			sector.unblock_tile(current_tile)
		queue_free()

# ── Drawing ───────────────────────────────────────────────────────────
func _draw() -> void:
	var size: Vector2 = data.get("size", Vector2(28, 28))
	var rect := Rect2(-size.x * 0.5, -size.y, size.x, size.y * 0.85)
	draw_rect(rect, data.get("swatch", DesignTokens.NIGHT_2), true)
	draw_rect(rect, data.get("edge", DesignTokens.NIGHT_0), false, 2.0)
	# Torches glow — translate light_radius into a simple circle stroke
	# at a warm tint so it reads at night without needing a real light.
	if data.has("light_radius"):
		var radius: float = float(data.light_radius) * 14.0
		var glow := Color(DesignTokens.GOLD_COIN.r, DesignTokens.GOLD_COIN.g, DesignTokens.GOLD_COIN.b, 0.18)
		draw_circle(Vector2(0, -size.y * 0.5), radius, glow)
	# HP pip.
	if hp < hp_max:
		var bar_w: float = size.x
		var bar_y: float = -size.y - 6.0
		var ratio: float = 0.0 if hp_max == 0.0 else hp / hp_max
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), DesignTokens.NIGHT_3, true)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, 3.0), DesignTokens.hp_color(ratio), true)
