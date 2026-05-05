class_name CardsData extends RefCounted
##
## Card definitions for v0. Six card types per faction, 15-card starter deck.
## Identical to godot-prototype/data/cards.gd — kept here so the tile
## rebuild can read the same shapes without reaching across folders.

# ── Buffalo deck ──────────────────────────────────────────────────────────
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

const ALL := {
	"card.calf": CalfCard,
	"card.ostrich": OstrichCard,
	"card.longhorn": LonghornCard,
	"card.production_node": ProductionNodeCard,
	"card.charge": ChargeCard,
	"card.stockpile": StockpileCard,
}

# Starter deck — Buffalo only for Phase 1 (the tile rebuild ports the
# canonical loop, not all three heroes). Total of 15 cards.
const STARTER_DECKS := {
	"Buffalo": [
		{"id": "card.calf", "count": 4},
		{"id": "card.ostrich", "count": 3},
		{"id": "card.longhorn", "count": 2},
		{"id": "card.production_node", "count": 3},
		{"id": "card.charge", "count": 2},
		{"id": "card.stockpile", "count": 1},
	],
}

const HAND_SIZE := 5

static func get_card(card_id: String) -> Dictionary:
	return ALL.get(card_id, {})

static func build_starter_deck(hero_id: String = "Buffalo") -> Array:
	var entries: Array = STARTER_DECKS.get(hero_id, STARTER_DECKS["Buffalo"])
	var deck: Array = []
	for entry in entries:
		for i in entry.count:
			deck.append(entry.id)
	return deck
