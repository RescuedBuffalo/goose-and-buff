class_name WeaponsData extends RefCounted
##
## Weapon stat table. CombatSystem.resolve_swing reads this to build the
## damage cone; GatherSystem reads gather_speed_multipliers to scale tool
## affinity (a hand axe pulls wood faster than bare hands).
##
## Distances are tile-grain. range_tiles is the cone length; arc_degrees
## is the FULL cone angle (resolver halves it internally for the dot
## test). Cooldown is wall-clock seconds.

const ALL := {
	"bare_hands": {
		"id": "bare_hands",
		"damage": 4.0,
		"range_tiles": 1,
		"arc_degrees": 90.0,
		"cooldown": 0.40,
		"display_name": "Bare hands",
		"gather_speed_multipliers": {
			# Bare hands gather everything at base rate — no boost.
		},
	},
	"hand_axe": {
		"id": "hand_axe",
		"damage": 12.0,
		"range_tiles": 1,
		"arc_degrees": 70.0,
		"cooldown": 0.55,
		"display_name": "Hand axe",
		"gather_speed_multipliers": {
			"wood": 3.0,
			"stone": 1.0,
			"berries": 1.0,
		},
	},
}

static func get_weapon(weapon_id: String) -> Dictionary:
	return ALL.get(weapon_id, ALL["bare_hands"])

static func gather_multiplier(weapon_id: String, resource_id: String) -> float:
	var weapon: Dictionary = get_weapon(weapon_id)
	var multipliers: Dictionary = weapon.get("gather_speed_multipliers", {})
	return float(multipliers.get(resource_id, 1.0))
