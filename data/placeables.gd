class_name PlaceablesData extends RefCounted
##
## Placeable catalog — walls, gates, torches, production nodes. BuildSystem
## reads this to validate placement and BuildOverlay to render the ghost.
## Placed objects spawn a Placeable adapter node parented to the world.
##
## recipe[item_id] = count — every placeable's cost is denominated in
## inventory items. The build system deducts these on place(); a partial
## inventory blocks the place attempt with reason="insufficient_resources".

const ALL := {
	"wood_wall": {
		"id": "wood_wall",
		"display_name": "Wood wall",
		"hp": 80.0,
		"recipe": {"wood": 4},
		"blocks_movement": true,
		"size": Vector2(40, 36),
		"swatch": Color8(120, 80, 50),
		"edge": Color8(64, 40, 24),
	},
	"gate": {
		"id": "gate",
		"display_name": "Gate",
		"hp": 120.0,
		"recipe": {"wood": 6},
		"blocks_movement": true,
		"can_open": false,  # MVP: gate is functionally a stronger wall
		"size": Vector2(44, 40),
		"swatch": Color8(170, 130, 80),
		"edge": Color8(80, 56, 32),
	},
	"torch": {
		"id": "torch",
		"display_name": "Torch",
		"hp": 20.0,
		"recipe": {"wood": 2},
		"blocks_movement": false,
		"light_radius": 4,  # tiles — visual cue only in MVP
		"size": Vector2(20, 36),
		"swatch": Color8(244, 196, 84),
		"edge": Color8(120, 80, 32),
	},
	"production_node": {
		"id": "production_node",
		"display_name": "Production node",
		"hp": 100.0,
		"recipe": {"wood": 6, "stone": 4},
		"blocks_movement": true,
		"size": Vector2(40, 44),
		"swatch": Color8(110, 70, 40),
		"edge": Color8(60, 36, 22),
	},
}

static func get_placeable(placeable_id: String) -> Dictionary:
	return ALL.get(placeable_id, {})

static func recipe(placeable_id: String) -> Dictionary:
	return get_placeable(placeable_id).get("recipe", {})

static func blocks_movement(placeable_id: String) -> bool:
	return bool(get_placeable(placeable_id).get("blocks_movement", false))
