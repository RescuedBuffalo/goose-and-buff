class_name WeaponsData extends RefCounted
##
## Weapon stat table. CombatSystem.resolve_swing reads this to build the
## damage cone (or projectile), GatherSystem reads gather_speed_multipliers
## to scale tool affinity (a hand axe pulls wood faster than bare hands).
##
## Distances are tile-grain. range_tiles is the cone length; arc_degrees
## is the FULL cone angle (resolver halves it internally for the dot
## test). Cooldown is wall-clock seconds.
##
## Kind:
##   "melee" — cone-arc swing (default)
##   "ranged" — projectile path; spawns an arrow node, consumes one
##              ammo from the inventory. ranged_projectile_id names the
##              ammo item to deduct (matching data/items.gd).
##
## M2 (BUF-149) adds iron / steel axe, spear, bow + arrow.

const KIND_MELEE := "melee"
const KIND_RANGED := "ranged"

const ALL := {
	"bare_hands": {
		"id": "bare_hands",
		"kind": KIND_MELEE,
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
		"kind": KIND_MELEE,
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
	# ── M2 weapon tiers (BUF-149) ──────────────────────────────────
	"iron_axe": {
		"id": "iron_axe",
		"kind": KIND_MELEE,
		"damage": 18.0,
		"range_tiles": 1,
		"arc_degrees": 70.0,
		"cooldown": 0.50,
		"display_name": "Iron axe",
		"gather_speed_multipliers": {
			"wood": 4.0,
			"stone": 1.5,
			"berries": 1.0,
		},
	},
	"steel_axe": {
		"id": "steel_axe",
		"kind": KIND_MELEE,
		"damage": 26.0,
		"range_tiles": 1,
		"arc_degrees": 70.0,
		"cooldown": 0.45,
		"display_name": "Steel axe",
		"gather_speed_multipliers": {
			"wood": 5.0,
			"stone": 2.0,
			"berries": 1.0,
		},
	},
	"spear": {
		"id": "spear",
		"kind": KIND_MELEE,
		"damage": 16.0,
		"range_tiles": 2,
		"arc_degrees": 35.0,
		"cooldown": 0.65,
		"display_name": "Long spear",
		"gather_speed_multipliers": {
			# Spears don't help with chopping — gather at base.
		},
	},
	"bow": {
		"id": "bow",
		"kind": KIND_RANGED,
		"damage": 22.0,
		"range_tiles": 6,
		"arc_degrees": 6.0,
		"cooldown": 0.80,
		"display_name": "Hunter's bow",
		"ranged_projectile_id": "arrow",
		"projectile_speed_px": 720.0,
		"gather_speed_multipliers": {},
	},
}

static func get_weapon(weapon_id: String) -> Dictionary:
	return ALL.get(weapon_id, ALL["bare_hands"])

static func gather_multiplier(weapon_id: String, resource_id: String) -> float:
	var weapon: Dictionary = get_weapon(weapon_id)
	var multipliers: Dictionary = weapon.get("gather_speed_multipliers", {})
	return float(multipliers.get(resource_id, 1.0))

static func is_ranged(weapon_id: String) -> bool:
	return String(get_weapon(weapon_id).get("kind", KIND_MELEE)) == KIND_RANGED

static func ammo_for(weapon_id: String) -> String:
	return String(get_weapon(weapon_id).get("ranged_projectile_id", ""))
