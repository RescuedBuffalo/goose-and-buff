class_name ResourcesData extends RefCounted
##
## Resource-node catalog. ResourceNode adapter and GatherSystem read this
## table — `hp` controls how long a node takes to deplete, `yields`
## controls what enters the inventory once the node breaks.
##
## yields[item_id] = [min, max] — the gather system picks an int in that
## range inclusive when the node is depleted. Respawn is out of MVP scope;
## once depleted, the node is gone for the rest of the run.

const ALL := {
	"tree_pine": {
		"id": "tree_pine",
		"display_name": "Pine",
		"hp": 20.0,
		"yields": {
			"wood": [3, 5],
		},
		"swatch": Color8(64, 96, 60),
		"trunk": Color8(80, 56, 36),
		"size": Vector2(38, 56),
		"blocks_movement": true,
	},
	"rock_field": {
		"id": "rock_field",
		"display_name": "Rocks",
		"hp": 30.0,
		"yields": {
			"stone": [2, 3],
		},
		"swatch": Color8(150, 144, 132),
		"trunk": Color8(96, 92, 86),
		"size": Vector2(40, 28),
		"blocks_movement": true,
	},
	"berry_bush": {
		"id": "berry_bush",
		"display_name": "Berry bush",
		"hp": 10.0,
		"yields": {
			"berries": [2, 4],
		},
		"swatch": Color8(120, 80, 96),
		"trunk": Color8(70, 50, 60),
		"size": Vector2(28, 22),
		"blocks_movement": false,
	},
}

static func get_resource(resource_id: String) -> Dictionary:
	return ALL.get(resource_id, {})

static func roll_yield(resource_id: String, rng: RandomNumberGenerator) -> Dictionary:
	# Picks a count for each item in the resource's yield table. Returns
	# {item_id: count}. Caller pushes each into the inventory.
	var data: Dictionary = get_resource(resource_id)
	var out: Dictionary = {}
	for item_id in data.get("yields", {}):
		var range_pair: Array = data.yields[item_id]
		var lo: int = int(range_pair[0])
		var hi: int = int(range_pair[1])
		var count: int = rng.randi_range(lo, hi)
		out[item_id] = count
	return out
