class_name ItemsData extends RefCounted
##
## Item catalog. Inventory slots reference items by id; placeables and
## weapons cross-reference back into placeables.gd / weapons.gd via the
## kind + payload fields.
##
## Phase 1 ships a small seed set:
##   - resources: wood, stone, berries
##   - weapons: bare_hands (pseudo-item, always equipped if no real weapon),
##              hand_axe
##   - placeables: wood_wall, gate, torch, production_node
##
## Stack sizes are conservative — the bottleneck is interesting tradeoffs,
## not arithmetic. A full inventory should feel earned but not crippling.

const KIND_RESOURCE := "resource"
const KIND_WEAPON := "weapon"
const KIND_PLACEABLE := "placeable"

const ALL := {
	"wood": {
		"id": "wood",
		"display_name": "Wood",
		"max_stack": 50,
		"kind": KIND_RESOURCE,
		"swatch": Color8(140, 92, 54),
	},
	"stone": {
		"id": "stone",
		"display_name": "Stone",
		"max_stack": 50,
		"kind": KIND_RESOURCE,
		"swatch": Color8(140, 134, 124),
	},
	"berries": {
		"id": "berries",
		"display_name": "Berries",
		"max_stack": 30,
		"kind": KIND_RESOURCE,
		"swatch": Color8(178, 60, 70),
	},
	"bare_hands": {
		"id": "bare_hands",
		"display_name": "Bare hands",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(220, 200, 178),
		"weapon_id": "bare_hands",
	},
	"hand_axe": {
		"id": "hand_axe",
		"display_name": "Hand axe",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(176, 142, 92),
		"weapon_id": "hand_axe",
	},
	"iron_axe": {
		"id": "iron_axe",
		"display_name": "Iron axe",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(170, 174, 178),
		"weapon_id": "iron_axe",
	},
	"steel_axe": {
		"id": "steel_axe",
		"display_name": "Steel axe",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(204, 212, 220),
		"weapon_id": "steel_axe",
	},
	"spear": {
		"id": "spear",
		"display_name": "Long spear",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(190, 162, 110),
		"weapon_id": "spear",
	},
	"bow": {
		"id": "bow",
		"display_name": "Hunter's bow",
		"max_stack": 1,
		"kind": KIND_WEAPON,
		"swatch": Color8(140, 110, 70),
		"weapon_id": "bow",
	},
	"arrow": {
		"id": "arrow",
		"display_name": "Arrows",
		"max_stack": 30,
		"kind": KIND_RESOURCE,
		"swatch": Color8(220, 200, 150),
	},
	"wood_wall": {
		"id": "wood_wall",
		"display_name": "Wood wall",
		"max_stack": 20,
		"kind": KIND_PLACEABLE,
		"swatch": Color8(120, 80, 50),
		"placeable_id": "wood_wall",
	},
	"gate": {
		"id": "gate",
		"display_name": "Gate",
		"max_stack": 5,
		"kind": KIND_PLACEABLE,
		"swatch": Color8(170, 130, 80),
		"placeable_id": "gate",
	},
	"torch": {
		"id": "torch",
		"display_name": "Torch",
		"max_stack": 10,
		"kind": KIND_PLACEABLE,
		"swatch": Color8(244, 196, 84),
		"placeable_id": "torch",
	},
	"production_node": {
		"id": "production_node",
		"display_name": "Production node",
		"max_stack": 3,
		"kind": KIND_PLACEABLE,
		"swatch": Color8(110, 70, 40),
		"placeable_id": "production_node",
	},
}

static func get_item(item_id: String) -> Dictionary:
	return ALL.get(item_id, {})

static func is_weapon(item_id: String) -> bool:
	var item: Dictionary = get_item(item_id)
	return item.get("kind", "") == KIND_WEAPON

static func is_placeable(item_id: String) -> bool:
	var item: Dictionary = get_item(item_id)
	return item.get("kind", "") == KIND_PLACEABLE

static func max_stack(item_id: String) -> int:
	return int(get_item(item_id).get("max_stack", 1))
