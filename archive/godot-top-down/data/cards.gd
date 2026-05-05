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

# ── Unlock pool ───────────────────────────────────────────────────────────
# Cards earned through meta-progression. Each carries a `replaces` field
# pointing at the starter-deck card it swaps in for — keeps the deck-builder
# UX a one-click toggle. Mechanics reuse existing payloads (unit_id, spawn_count,
# coin_delta, building_id) so no new logic is needed in the adapter.

# Buffalo unlocks
const CalfPairCard := {
	"id": "card.calf_pair", "name": "Calf pair", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 50,
	"description": "Spawn two Calves. The pair holds longer than the part.",
	"flavor": "They walk in step now.",
	"replaces": "card.calf",
	"payload": {"unit_id": "Calf", "spawn_count": 2},
}

const CalfMilitiaCard := {
	"id": "card.calf_militia", "name": "Calf militia", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 75,
	"description": "Spawn three Calves. Cheap bodies, packed tight.",
	"flavor": "Wide stance, three abreast.",
	"replaces": "card.calf",
	"payload": {"unit_id": "Calf", "spawn_count": 3},
}

const OstrichPairCard := {
	"id": "card.ostrich_pair", "name": "Ostrich pair", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 70,
	"description": "Spawn two Ostriches. Two kicks, twice the knockback.",
	"flavor": "They take turns. Mostly.",
	"replaces": "card.ostrich",
	"payload": {"unit_id": "Ostrich", "spawn_count": 2},
}

const LonghornEliteCard := {
	"id": "card.longhorn_elite", "name": "Longhorn elite", "faction": "Buffalo",
	"kind": "unit", "phase": "prep", "cost": 65,
	"description": "Spawn one Longhorn at a discount. Trained line-holder.",
	"flavor": "Knows where the line is.",
	"replaces": "card.longhorn",
	"payload": {"unit_id": "Longhorn"},
}

const GreaterStockpileCard := {
	"id": "card.greater_stockpile", "name": "Greater stockpile", "faction": "Buffalo",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 60 coin to the balance immediately.",
	"flavor": "What was set aside, doubled.",
	"replaces": "card.stockpile",
	"payload": {"coin_delta": 60},
}

const WarhornCard := {
	"id": "card.warhorn", "name": "Warhorn", "faction": "Buffalo",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 40 coin and steadies the line.",
	"flavor": "Heard before it's seen.",
	"replaces": "card.stockpile",
	"payload": {"coin_delta": 40},
}

const ThriftNodeCard := {
	"id": "card.thrift_node", "name": "Thrift node", "faction": "Buffalo",
	"kind": "building", "phase": "prep", "cost": 35,
	"description": "Cheaper production node. Same hum, fewer parts.",
	"flavor": "Found in the back of a barn.",
	"replaces": "card.production_node",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
}

# Goose unlocks
const GoslingPairCard := {
	"id": "card.gosling_pair", "name": "Gosling pair", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 40,
	"description": "Spawn two Goslings. They scrap better in twos.",
	"flavor": "Less brave alone.",
	"replaces": "card.gosling",
	"payload": {"unit_id": "Gosling", "spawn_count": 2},
}

const GoslingFlockCard := {
	"id": "card.gosling_flock", "name": "Gosling flock", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 60,
	"description": "Spawn three Goslings. A wave of feathers.",
	"flavor": "Loud — by design.",
	"replaces": "card.gosling",
	"payload": {"unit_id": "Gosling", "spawn_count": 3},
}

const HeronPairCard := {
	"id": "card.heron_pair", "name": "Heron pair", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 65,
	"description": "Spawn two Herons. Two long strikes, far back.",
	"flavor": "Patient at both ends.",
	"replaces": "card.heron",
	"payload": {"unit_id": "Heron", "spawn_count": 2},
}

const HeronPostCard := {
	"id": "card.heron_post", "name": "Heron post", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 30,
	"description": "Spawn one Heron at a discount. Cheap eyes on the back.",
	"flavor": "Posted up. Watching.",
	"replaces": "card.heron",
	"payload": {"unit_id": "Heron"},
}

const SwanEliteCard := {
	"id": "card.swan_elite", "name": "Swan elite", "faction": "Goose",
	"kind": "unit", "phase": "prep", "cost": 60,
	"description": "Spawn one Swan at a discount. Same hiss, better price.",
	"flavor": "Still surprisingly mean.",
	"replaces": "card.swan",
	"payload": {"unit_id": "Swan"},
}

const GreaterStockpileGooseCard := {
	"id": "card.greater_stockpile_goose", "name": "Greater stockpile", "faction": "Goose",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 60 coin to the balance immediately.",
	"flavor": "Pulled from the back of the nest.",
	"replaces": "card.stockpile_goose",
	"payload": {"coin_delta": 60},
}

const ThriftNodeGooseCard := {
	"id": "card.thrift_node_goose", "name": "Thrift node", "faction": "Goose",
	"kind": "building", "phase": "prep", "cost": 35,
	"description": "Cheaper production node. Quiet little hum.",
	"flavor": "Stashed under a wing.",
	"replaces": "card.production_node_goose",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
}

# Fox unlocks
const KitPairCard := {
	"id": "card.kit_pair", "name": "Kit pair", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 45,
	"description": "Spawn two Kits. They take corners together.",
	"flavor": "Twice the bite.",
	"replaces": "card.kit",
	"payload": {"unit_id": "Kit", "spawn_count": 2},
}

const KitPackCard := {
	"id": "card.kit_pack", "name": "Kit pack", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 65,
	"description": "Spawn three Kits. The seam is wherever they say it is.",
	"flavor": "All teeth, no plan.",
	"replaces": "card.kit",
	"payload": {"unit_id": "Kit", "spawn_count": 3},
}

const LynxPairCard := {
	"id": "card.lynx_pair", "name": "Lynx pair", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 80,
	"description": "Spawn two Lynxes. Two ambushes from the back rank.",
	"flavor": "Each picks its own.",
	"replaces": "card.lynx",
	"payload": {"unit_id": "Lynx", "spawn_count": 2},
}

const LynxPostCard := {
	"id": "card.lynx_post", "name": "Lynx post", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 40,
	"description": "Spawn one Lynx at a discount. Quiet sentry.",
	"flavor": "First strike, always.",
	"replaces": "card.lynx",
	"payload": {"unit_id": "Lynx"},
}

const BadgerEliteCard := {
	"id": "card.badger_elite", "name": "Badger elite", "faction": "Fox",
	"kind": "unit", "phase": "prep", "cost": 60,
	"description": "Spawn one Badger at a discount. Knows the trick.",
	"flavor": "Stocky, stubborn, cheap.",
	"replaces": "card.badger",
	"payload": {"unit_id": "Badger"},
}

const GreaterStockpileFoxCard := {
	"id": "card.greater_stockpile_fox", "name": "Greater stockpile", "faction": "Fox",
	"kind": "resource", "phase": "prep", "cost": 0,
	"description": "Adds 60 coin to the balance immediately.",
	"flavor": "Two lean weeks, stashed.",
	"replaces": "card.stockpile_fox",
	"payload": {"coin_delta": 60},
}

const ThriftNodeFoxCard := {
	"id": "card.thrift_node_fox", "name": "Thrift node", "faction": "Fox",
	"kind": "building", "phase": "prep", "cost": 35,
	"description": "Cheaper production node. Hum at the back of the den.",
	"flavor": "Salvaged, useful.",
	"replaces": "card.production_node_fox",
	"payload": {"building_id": "ProductionNode", "coin_per_second": 5.0},
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
	# Unlock pool
	"card.calf_pair": CalfPairCard,
	"card.calf_militia": CalfMilitiaCard,
	"card.ostrich_pair": OstrichPairCard,
	"card.longhorn_elite": LonghornEliteCard,
	"card.greater_stockpile": GreaterStockpileCard,
	"card.warhorn": WarhornCard,
	"card.thrift_node": ThriftNodeCard,
	"card.gosling_pair": GoslingPairCard,
	"card.gosling_flock": GoslingFlockCard,
	"card.heron_pair": HeronPairCard,
	"card.heron_post": HeronPostCard,
	"card.swan_elite": SwanEliteCard,
	"card.greater_stockpile_goose": GreaterStockpileGooseCard,
	"card.thrift_node_goose": ThriftNodeGooseCard,
	"card.kit_pair": KitPairCard,
	"card.kit_pack": KitPackCard,
	"card.lynx_pair": LynxPairCard,
	"card.lynx_post": LynxPostCard,
	"card.badger_elite": BadgerEliteCard,
	"card.greater_stockpile_fox": GreaterStockpileFoxCard,
	"card.thrift_node_fox": ThriftNodeFoxCard,
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

# Unlock pool per hero. Lists card ids the player can unlock between runs and
# swap into that hero's deck. The order here drives the Lodge's display order.
const UNLOCK_POOLS := {
	"Buffalo": [
		"card.calf_pair",
		"card.calf_militia",
		"card.ostrich_pair",
		"card.longhorn_elite",
		"card.greater_stockpile",
		"card.warhorn",
		"card.thrift_node",
	],
	"Goose": [
		"card.gosling_pair",
		"card.gosling_flock",
		"card.heron_pair",
		"card.heron_post",
		"card.swan_elite",
		"card.greater_stockpile_goose",
		"card.thrift_node_goose",
	],
	"Fox": [
		"card.kit_pair",
		"card.kit_pack",
		"card.lynx_pair",
		"card.lynx_post",
		"card.badger_elite",
		"card.greater_stockpile_fox",
		"card.thrift_node_fox",
	],
}

static func get_card(card_id: String) -> Dictionary:
	return ALL.get(card_id, {})

static func build_starter_deck(hero_id: String = "Buffalo") -> Array:
	var entries: Array = STARTER_DECKS.get(hero_id, STARTER_DECKS["Buffalo"])
	var deck: Array = []
	for entry in entries:
		for i in entry.count:
			deck.append(entry.id)
	return deck

# Apply the player's unlocked-card swaps to a starter deck. `swaps` maps a
# starter card id to an unlocked card id; one occurrence of the starter is
# replaced per entry. Unmatched entries (e.g. a swap whose starter isn't in
# the deck for some reason) are silently skipped.
static func apply_swaps(deck: Array, swaps: Dictionary) -> Array:
	var result := deck.duplicate()
	for starter_id in swaps.keys():
		var unlocked_id: String = swaps[starter_id]
		var idx := result.find(starter_id)
		if idx != -1:
			result[idx] = unlocked_id
	return result
