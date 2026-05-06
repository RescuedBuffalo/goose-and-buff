extends Node2D
##
## Resource node adapter — pine, rocks, berries. Holds its kind, current
## HP, and a tile coord. Subscribes to GatherSystem signals to update its
## visible HP bar; depletes off-screen via the gather system mutating its
## own scalars (we sync from gather_progress emissions).
##
## When the node is depleted, GatherSystem emits gather_completed; main
## listens for that and calls deplete() on the node, which queues the
## node free + unblocks the AStar tile if the node was a movement
## blocker.

const Resources := preload("res://data/resources.gd")

@export var resource_kind: String = "tree_pine"

var data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var current_tile: Vector2i = Vector2i.ZERO
var sector: Node = null
var _gather_progress_visible: float = 0.0  # 0..1

func configure(kind: String) -> void:
	resource_kind = kind

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func place_at_tile(tile: Vector2i) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)
		# Block movement on the tile we just landed on. Done here, not
		# in _ready, because _ready fires before main calls place_at_tile
		# and would otherwise block tile (0, 0) by mistake.
		if data.get("blocks_movement", false):
			sector.block_tile(current_tile)

func _ready() -> void:
	data = Resources.get_resource(resource_kind)
	hp_max = float(data.hp)
	hp = hp_max
	add_to_group("resource_nodes")
	y_sort_enabled = true
	queue_redraw()

func resource_kind_id() -> String:
	return resource_kind

func update_progress(remaining: float) -> void:
	hp = remaining
	_gather_progress_visible = clamp(1.0 - (hp / hp_max), 0.0, 1.0)
	queue_redraw()

func clear_progress() -> void:
	# Called when a gather is cancelled (hero walked away). Drops the
	# progress bar back to invisible so the partial sliver doesn't
	# linger between attempts. HP is preserved — the tree only goes
	# back to full when fully respawned (out of MVP scope).
	_gather_progress_visible = 0.0
	queue_redraw()

func deplete() -> void:
	if sector != null and data.get("blocks_movement", false):
		sector.unblock_tile(current_tile)
	queue_free()

# ── Drawing ───────────────────────────────────────────────────────────
func _draw() -> void:
	var size: Vector2 = data.get("size", Vector2(28, 28))
	var trunk_size := Vector2(size.x * 0.35, size.y * 0.35)
	var trunk_rect := Rect2(-trunk_size.x * 0.5, -trunk_size.y, trunk_size.x, trunk_size.y)
	draw_rect(trunk_rect, data.get("trunk", DesignTokens.NIGHT_2), true)
	# Foliage / body — the visible "tree top" or "rock cluster".
	var body_rect := Rect2(-size.x * 0.5, -size.y, size.x, size.y * 0.75)
	draw_rect(body_rect, data.swatch, true)
	draw_rect(body_rect, DesignTokens.NIGHT_0, false, 1.5)
	# Gather progress bar above when actively being gathered.
	if _gather_progress_visible > 0.001 and _gather_progress_visible < 1.0:
		var bar_w: float = size.x
		var bar_y: float = -size.y - 8.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), DesignTokens.NIGHT_3, true)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * _gather_progress_visible, 3.0),
				DesignTokens.PARCHMENT_0, true)
