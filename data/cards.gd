class_name CardsData extends RefCounted
##
## Card definitions for v0. Six card types, 15-card starter deck.
##
## kind:        "unit" | "building" | "ability" | "resource"
## faction:     drives palette + totem
## phase:       which phase the card is playable in. Unit/building/resource
##              are prep-only; ability cards are wave-only.
## payload:    kind-specific data the logic layer hands to the spawner.
##
## Costs and unit references mirror units-data.md. Don't tune balance here
## without re-reading the spec note about compounding tilts.

const CalfCard := {
	"id": "card.calf", "name": "Calf", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 28,
	"description": "Spawn one Calf. Light melee. Walks toward the line.",
	"flavor": "Wide stance from the start.",
	"payload": {"unit_id": "Calf"},
}

const OstrichCard := {
	"id": "card.ostrich", "name": "Ostrich", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 40,
	"description": "Spawn one Ostrich. Mid-range kick with knockback.",
	"flavor": "Kicks at mid-range. Knockback included.",
	"payload": {"unit_id": "Ostrich"},
}

const LonghornCard := {
	"id": "card.longhorn", "name": "Longhorn", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 80,
	"description": "Spawn one Longhorn. The wall.",
	"flavor": "Don't try to go through.",
	"payload": {"unit_id": "Longhorn"},
}

const ProductionNodeCard := {
	"id": "card.production_node", "name": "Production node", "faction": "Buffalo",
	"kind": "building", "phase": "prep", "cost": 50,
	"description": "Generates 5 coin per second. One per sector.",
	"flavor": "The hum of a working line.",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
}

const ChargeCard := {
	"id": "card.charge", "name": "Buffalo charge", "faction": "Buffalo",
	"kind": "ability", "phase": "wave", "cost": 0,
	"description": "Line AoE. Damage and knockback along the cast direction.",
	"flavor": "Hold the line by breaking it first.",
	"payload": {
		"ability_id": "BuffaloCharge",
		"length": 320.0,
		"width": 64.0,
		"damage": 30.0,
		"knockback": 64.0,
	},
}

const StockpileCard := {
	"id": "card.stockpile", "name": "Stockpile", "faction": "Buffalo",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 30 coin to the balance immediately.",
	"flavor": "What was set aside, withdrawn.",
	"payload": {"coin_delta": 30},
}

# ─── Fox starter deck ─────────────────────────────────────────────────────
# Mirrors the Buffalo template: light/ranged/heavy unit, production node,
# signature ability, stockpile. Costs follow units-data — Kit/Lynx/Badger
# are slightly cheaper than Buffalo equivalents in line with the assassin
# tilt (lower HP, higher per-attack damage, faster pressure).

const KitCard := {
	"id": "card.kit", "name": "Kit", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 25,
	"description": "Spawn one Kit. Quick light melee.",
	"flavor": "Faster than it should be.",
	"payload": {"unit_id": "Kit"},
}

const LynxCard := {
	"id": "card.lynx", "name": "Lynx", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 45,
	"description": "Spawn one Lynx. Stalking ranged striker — bonus damage on the first hit.",
	"flavor": "Stalks. Strikes once, hard.",
	"payload": {"unit_id": "Lynx"},
}

const BadgerCard := {
	"id": "card.badger", "name": "Badger", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 70,
	"description": "Spawn one Badger. Stocky bruiser with a chance to dodge.",
	"flavor": "Stocky and stubborn. Hard to pin down.",
	"payload": {"unit_id": "Badger"},
}

const FoxProductionNodeCard := {
	"id": "card.fox_production_node", "name": "Production node", "faction": "Fox",
	"kind": "building", "phase": "prep", "cost": 50,
	"description": "Generates 5 coin per second. One per sector.",
	"flavor": "Quiet hum at the back of the den.",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
}

const SnatchCard := {
	"id": "card.snatch", "name": "Snatch", "faction": "Fox",
	"kind": "ability", "phase": "wave", "cost": 0,
	"description": "Dash to a target. Strike on arrival; bonus damage from behind.",
	"flavor": "Pick the seam, take what's loose.",
	"payload": {
		"ability_id": "Snatch",
		# Pixels — caps the dash so Snatch doesn't substitute for movement.
		# Roughly one second of Fox's run speed (22 studs * 12 px/stud).
		"max_dash": 240.0,
		# Strike radius around the dash endpoint.
		"strike_radius": 44.0,
		"damage": 22.0,
		# Backstab fires when the hero ends up at-or-behind the enemy along
		# the enemy's facing direction (enemies face left toward the core).
		"backstab_multiplier": 2.0,
	},
}

const FoxStockpileCard := {
	"id": "card.fox_stockpile", "name": "Stockpile", "faction": "Fox",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 30 coin to the balance immediately.",
	"flavor": "Cached for the lean week.",
	"payload": {"coin_delta": 30},
}

const ALL := {
	"card.calf": CalfCard,
	"card.ostrich": OstrichCard,
	"card.longhorn": LonghornCard,
	"card.production_node": ProductionNodeCard,
	"card.charge": ChargeCard,
	"card.stockpile": StockpileCard,
	"card.kit": KitCard,
	"card.lynx": LynxCard,
	"card.badger": BadgerCard,
	"card.fox_production_node": FoxProductionNodeCard,
	"card.snatch": SnatchCard,
	"card.fox_stockpile": FoxStockpileCard,
}

# Starter decks: id repeated `count` times, keyed by faction. Counts mirror
# the Buffalo template across factions so each hero opens with the same
# 15-card shape — faction tilt comes from unit stats and signature ability,
# not deck composition.
const STARTER_DECKS := {
	"Buffalo": [
		{"id": "card.calf", "count": 4},
		{"id": "card.ostrich", "count": 3},
		{"id": "card.longhorn", "count": 2},
		{"id": "card.production_node", "count": 3},
		{"id": "card.charge", "count": 2},
		{"id": "card.stockpile", "count": 1},
	],
	"Fox": [
		{"id": "card.kit", "count": 4},
		{"id": "card.lynx", "count": 3},
		{"id": "card.badger", "count": 2},
		{"id": "card.fox_production_node", "count": 3},
		{"id": "card.snatch", "count": 2},
		{"id": "card.fox_stockpile", "count": 1},
	],
}

const HAND_SIZE := 5

static func get_card(card_id: String) -> Dictionary:
	return ALL.get(card_id, {})

static func build_starter_deck(faction: String = "Buffalo") -> Array:
	# Fall back to Buffalo so an unknown faction never hard-fails — the
	# dispatcher upstream is the one place we check the faction is real.
	var entries: Array = STARTER_DECKS.get(faction, STARTER_DECKS["Buffalo"])
	var deck: Array = []
	for entry in entries:
		for i in entry.count:
			deck.append(entry.id)
	return deck
