class_name BuildSystem extends RefCounted
##
## Pure placement validator. The adapter shows a ghost preview at the
## cursor; on click it asks BuildSystem.can_place(item_id, tile) and
## then BuildSystem.place(item_id, tile, inventory) to deduct the
## recipe and announce the placement.
##
## The actual scene-side spawn (creating a Placeable Node2D, updating
## AStarGrid2D) is the adapter's job — BuildSystem only owns the
## "is this legal? did the recipe pay?" question.
##
## World state is queried through a callable so the system stays pure.
## main.gd hands in `is_tile_open(tile) -> bool` which combines the
## sector's walkability check with adapter-side knowledge of placeables
## already on that tile.

const Items := preload("res://data/items.gd")
const Placeables := preload("res://data/placeables.gd")

const REASON_NOT_PLACEABLE := "not_placeable"
const REASON_BLOCKED := "blocked"
const REASON_NO_RESOURCES := "no_resources"
const REASON_OUT_OF_BOUNDS := "out_of_bounds"

signal placed(item_id: String, tile: Vector2i)
signal place_rejected(item_id: String, reason: String)

func can_place(item_id: String, tile: Vector2i, inventory: InventorySystem, is_tile_open: Callable) -> Dictionary:
	if not Items.is_placeable(item_id):
		return {"ok": false, "reason": REASON_NOT_PLACEABLE}
	if not is_tile_open.call(tile):
		return {"ok": false, "reason": REASON_BLOCKED}
	if not _has_recipe(item_id, inventory):
		return {"ok": false, "reason": REASON_NO_RESOURCES}
	return {"ok": true}

func place(item_id: String, tile: Vector2i, inventory: InventorySystem, is_tile_open: Callable) -> Dictionary:
	var check: Dictionary = can_place(item_id, tile, inventory, is_tile_open)
	if not check.ok:
		place_rejected.emit(item_id, check.reason)
		return check
	# Deduct recipe before announcing — placed listeners may add to the
	# inventory (e.g. drop a previous structure on demolish), and we don't
	# want to leak resources.
	var item: Dictionary = Items.get_item(item_id)
	var placeable_id: String = item.get("placeable_id", "")
	var recipe: Dictionary = Placeables.recipe(placeable_id)
	for ingredient_id in recipe:
		inventory.remove_item(ingredient_id, int(recipe[ingredient_id]))
	placed.emit(item_id, tile)
	return {"ok": true, "placeable_id": placeable_id, "tile": tile}

# ── internals ─────────────────────────────────────────────────────────

func _has_recipe(item_id: String, inventory: InventorySystem) -> bool:
	var item: Dictionary = Items.get_item(item_id)
	var placeable_id: String = item.get("placeable_id", "")
	var recipe: Dictionary = Placeables.recipe(placeable_id)
	for ingredient_id in recipe:
		if not inventory.has_at_least(ingredient_id, int(recipe[ingredient_id])):
			return false
	return true
