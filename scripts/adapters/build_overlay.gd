extends Node2D
##
## Build overlay — runs alongside the sector, listens to inventory
## selection + cursor position, asks BuildSystem whether the cursor's
## tile is a legal place. Tells the sector adapter to draw the ghost
## diamond at that tile in green or red.
##
## On left click while a placeable is selected, fires a place request
## upward to main via the place_requested signal. Main is the only thing
## that knows how to spawn the actual placeable Node — overlay's job is
## just preview + intent.

const Items := preload("res://data/items.gd")

signal place_requested(item_id: String, tile: Vector2i)

var sector: Node = null
var inventory: InventorySystem = null
var build_system: BuildSystem = null

func attach(sector_node: Node, inventory_logic: InventorySystem, build_logic: BuildSystem) -> void:
	sector = sector_node
	inventory = inventory_logic
	build_system = build_logic

func _process(_delta: float) -> void:
	if sector == null or inventory == null or build_system == null:
		return
	# Stop updating the ghost preview once the run ends — otherwise the
	# cursor keeps painting a green/red diamond behind the end-screen
	# scrim. Mirrors main.gd's tick guard.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		sector.clear_build_ghost()
		return
	var item_id: String = inventory.selected_item_id()
	if item_id.is_empty() or not Items.is_placeable(item_id):
		sector.clear_build_ghost()
		return
	var tile: Vector2i = sector.world_to_tile(get_global_mouse_position())
	var check: Dictionary = build_system.can_place(item_id, tile, inventory, Callable(sector, "is_tile_walkable"))
	sector.set_build_ghost(tile, check.ok)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if sector == null or inventory == null or build_system == null:
		return
	var item_id: String = inventory.selected_item_id()
	if item_id.is_empty() or not Items.is_placeable(item_id):
		return
	var tile: Vector2i = sector.world_to_tile(get_global_mouse_position())
	var check: Dictionary = build_system.can_place(item_id, tile, inventory, Callable(sector, "is_tile_walkable"))
	if not check.ok:
		return
	get_viewport().set_input_as_handled()
	place_requested.emit(item_id, tile)
