class_name CardsData extends RefCounted
##
## Card definitions for v0. Six card types per faction, 15-card starter deck.
##
## kind:        "unit" | "building" | "ability" | "resource"
## faction:     drives palette + totem
## phase:       which phase the card is playable in. Unit/building/resource
##              are prep-only; ability cards are wave-only.
## payload:    kind-specific data the logic layer hands to the spawner.
##
## Costs and unit references mirror units-data.md. Don't tune balance here
## without re-reading the spec note about compounding tilts.

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

# ── Goose deck ────────────────────────────────────────────────────────────
const GoslingCard := {
	"id": "card.gosling", "name": "Gosling", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 22,
	"description": "Spawn one Gosling. Cheap, fast, dies cheap.",
	"flavor": "In numbers, scrappy. Alone, brave.",
	"payload": {"unit_id": "Gosling"},
}

const HeronCard := {
	"id": "card.heron", "name": "Heron", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 35,
	"description": "Spawn one Heron. Long spear-strike from the back.",
	"flavor": "Stays back. Strikes long.",
	"payload": {"unit_id": "Heron"},
}

const SwanCard := {
	"id": "card.swan", "name": "Swan", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 70,
	"description": "Spawn one Swan. Hisses, charges, holds.",
	"flavor": "Surprisingly mean.",
	"payload": {"unit_id": "Swan"},
}

# Mechanics-identical to the Buffalo node — distinct id keeps the card art
# tinted to the Goose palette via the `faction` field.
const ProductionNodeCardGoose := {
	"id": "card.production_node_goose", "name": "Production node", "faction": "Goose",
	"kind": "building", "phase": "prep", "cost": 50,
	"description": "Generates 5 coin per second. One per sector.",
	"flavor": "The hum of a working line.",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
}

const DiveCard := {
	"id": "card.dive", "name": "Dive", "faction": "Goose",
	"kind": "ability", "phase": "wave", "cost": 0,
	"description": "Cone AoE in front. Damage and knockback.",
	"flavor": "Wings tucked, beak first.",
	"payload": {
		"ability_id": "Dive",
		"length": 220.0,
		"half_angle_deg": 32.0,
		"damage": 26.0,
		"knockback": 56.0,
	},
}

const StockpileCardGoose := {
	"id": "card.stockpile_goose", "name": "Stockpile", "faction": "Goose",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 30 coin to the balance immediately.",
	"flavor": "What was set aside, withdrawn.",
	"payload": {"coin_delta": 30},
}

# ── Fox deck ──────────────────────────────────────────────────────────────
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

const ProductionNodeCardFox := {
	"id": "card.production_node_fox", "name": "Production node", "faction": "Fox",
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

const StockpileCardFox := {
	"id": "card.stockpile_fox", "name": "Stockpile", "faction": "Fox",
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
	"card.gosling": GoslingCard,
	"card.heron": HeronCard,
	"card.swan": SwanCard,
	"card.production_node_goose": ProductionNodeCardGoose,
	"card.dive": DiveCard,
	"card.stockpile_goose": StockpileCardGoose,
	"card.kit": KitCard,
	"card.lynx": LynxCard,
	"card.badger": BadgerCard,
	"card.production_node_fox": ProductionNodeCardFox,
	"card.snatch": SnatchCard,
	"card.stockpile_fox": StockpileCardFox,
}

# Starter decks per hero. id repeated `count` times.
# Buffalo holds the canonical 4-3-2-3-2-1 template.
# Goose tilts a Heron slot into a Gosling (5-2-2-3-2-1) — same total, leans
# the hand swarm-heavy as called out in BUF-106.
# Fox follows the Buffalo template (4-3-2-3-2-1) — its faction tilt comes
# from per-unit stats (assassin: low HP, high damage) rather than deck shape.
const STARTER_DECKS := {
	"Buffalo": [
		{"id": "card.calf", "count": 4},
		{"id": "card.ostrich", "count": 3},
		{"id": "card.longhorn", "count": 2},
		{"id": "card.production_node", "count": 3},
		{"id": "card.charge", "count": 2},
		{"id": "card.stockpile", "count": 1},
	],
	"Goose": [
		{"id": "card.gosling", "count": 5},
		{"id": "card.heron", "count": 2},
		{"id": "card.swan", "count": 2},
		{"id": "card.production_node_goose", "count": 3},
		{"id": "card.dive", "count": 2},
		{"id": "card.stockpile_goose", "count": 1},
	],
	"Fox": [
		{"id": "card.kit", "count": 4},
		{"id": "card.lynx", "count": 3},
		{"id": "card.badger", "count": 2},
		{"id": "card.production_node_fox", "count": 3},
		{"id": "card.snatch", "count": 2},
		{"id": "card.stockpile_fox", "count": 1},
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
