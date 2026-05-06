class_name UpgradesData extends RefCounted
##
## Lodge upgrade pool (BUF-147 / BUF-149). Spent in embers between runs;
## stacks once-per-id (no levels — branch the upgrade if you want stacking
## variants for now). Pure data — `scripts/logic/stat_system.gd` reads
## this to compute effective_stats from owned ids.
##
## Each upgrade:
##   id: String — stable, lower-snake. Used in save state + telemetry.
##   hero: String — "Buffalo" | "Goose" | "Fox" | "Shared". Per-hero
##                   upgrades only apply when that hero is selected;
##                   "Shared" applies to every hero.
##   tier: int — 1..3, the depth in the tree. Earlier tiers must be
##                purchased before later (prereq).
##   prereq: String — id of the upgrade required to unlock this one
##                    (empty for tier-1 entries).
##   cost: int — embers required to purchase.
##   modifiers: Array[Dictionary] — flat / pct stat changes.
##                  {stat, kind: "flat"|"pct", amount}
##   unlocks: Array[String] — item / weapon ids granted on purchase.
##   display_name, description: voice-rule strings (sentence case).
##
## Stats it can modify (the closed enumeration in stat_system.gd):
##   hp_max, attack_damage, attack_speed, attack_range, gather_speed,
##   build_speed, move_speed, ability_cooldown, lodge_hp_max,
##   inventory_slots
##
## Voice rule: upgrade names use sentence case + warm + nouns-first.
## Skip RPG-menu language ("Mastery I"), prefer image-bearing ("Iron-shod
## boots", "Lantern oil reserve").
##
## ability_cooldown disclosure: hero abilities (Q-bound charge / dive /
## snatch) aren't wired in M2 — `effective_stats.ability_cooldown` is
## stamped into GameState.signature_cooldown_max at run start so the
## value lands at the contract point abilities will read once they ship
## (BUF-150-ish). Until then, upgrades that touch ability_cooldown say
## so in their description so the player isn't misled into spending an
## ember on a stat with no live consumer.

const HERO_BUFFALO := "Buffalo"
const HERO_GOOSE := "Goose"
const HERO_FOX := "Fox"
const HERO_SHARED := "Shared"

const ALL := [
	# ── Shared tier 1 ──────────────────────────────────────────────
	{
		"id": "shared_iron_axe",
		"hero": HERO_SHARED,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Iron axe at the lodge",
		"description": "An iron axe waits in your slot. Wood comes faster than the hand axe.",
		"modifiers": [],
		"unlocks": ["iron_axe"],
	},
	{
		"id": "shared_warm_cloak",
		"hero": HERO_SHARED,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Warm cloak",
		"description": "A heavier hide on your shoulders. You start each run a little tougher.",
		"modifiers": [
			{"stat": "hp_max", "kind": "flat", "amount": 20.0},
		],
		"unlocks": [],
	},
	{
		"id": "shared_quick_hands",
		"hero": HERO_SHARED,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Quick hands",
		"description": "Practice tells. Each gather goes a little faster.",
		"modifiers": [
			{"stat": "gather_speed", "kind": "pct", "amount": 0.15},
		],
		"unlocks": [],
	},
	{
		"id": "shared_extra_pouch",
		"hero": HERO_SHARED,
		"tier": 1,
		"prereq": "",
		"cost": 2,
		"display_name": "Extra pouch",
		"description": "Stitched a side pocket. One more inventory slot.",
		"modifiers": [
			{"stat": "inventory_slots", "kind": "flat", "amount": 1.0},
		],
		"unlocks": [],
	},
	# ── Shared tier 2 ──────────────────────────────────────────────
	{
		"id": "shared_spear",
		"hero": HERO_SHARED,
		"tier": 2,
		"prereq": "shared_iron_axe",
		"cost": 2,
		"display_name": "Long spear",
		"description": "A spear unlocks. Reaches further than the axe.",
		"modifiers": [],
		"unlocks": ["spear"],
	},
	{
		"id": "shared_lodge_thicker_walls",
		"hero": HERO_SHARED,
		"tier": 2,
		"prereq": "shared_warm_cloak",
		"cost": 2,
		"display_name": "Thicker lodge walls",
		"description": "The lodge takes more before it falls.",
		"modifiers": [
			{"stat": "lodge_hp_max", "kind": "pct", "amount": 0.20},
		],
		"unlocks": [],
	},
	{
		"id": "shared_oilskin_grip",
		"hero": HERO_SHARED,
		"tier": 2,
		"prereq": "shared_quick_hands",
		"cost": 2,
		"display_name": "Oilskin grip",
		"description": "The axe doesn't slip. Swing a touch faster.",
		"modifiers": [
			{"stat": "attack_speed", "kind": "pct", "amount": 0.12},
		],
		"unlocks": [],
	},
	{
		"id": "shared_steel_axe",
		"hero": HERO_SHARED,
		"tier": 2,
		"prereq": "shared_iron_axe",
		"cost": 3,
		"display_name": "Steel axe at the lodge",
		"description": "A steel axe takes the place of the iron one. Each swing bites deeper.",
		"modifiers": [],
		"unlocks": ["steel_axe"],
	},
	# ── Shared tier 3 ──────────────────────────────────────────────
	{
		"id": "shared_bow",
		"hero": HERO_SHARED,
		"tier": 3,
		"prereq": "shared_spear",
		"cost": 3,
		"display_name": "Hunter's bow",
		"description": "A bow joins the lodge stash. Shoots at range; arrows from the inventory.",
		"modifiers": [],
		"unlocks": ["bow", "arrow"],
	},
	{
		"id": "shared_lantern_oil",
		"hero": HERO_SHARED,
		"tier": 3,
		"prereq": "shared_lodge_thicker_walls",
		"cost": 3,
		"display_name": "Lantern oil reserve",
		"description": "Bigger reserve in the lodge wall sconces. The lodge stands longer still.",
		"modifiers": [
			{"stat": "lodge_hp_max", "kind": "pct", "amount": 0.20},
		],
		"unlocks": [],
	},
	{
		"id": "shared_practiced_arm",
		"hero": HERO_SHARED,
		"tier": 3,
		"prereq": "shared_oilskin_grip",
		"cost": 3,
		"display_name": "Practiced arm",
		"description": "Every swing lands harder than it has any right to.",
		"modifiers": [
			{"stat": "attack_damage", "kind": "pct", "amount": 0.20},
		],
		"unlocks": [],
	},

	# ── Buffalo — anchor / soak ────────────────────────────────────
	{
		"id": "buffalo_thick_hide",
		"hero": HERO_BUFFALO,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Thick hide",
		"description": "Bigger frame, more to take. Buffalo HP up.",
		"modifiers": [
			{"stat": "hp_max", "kind": "pct", "amount": 0.15},
		],
		"unlocks": [],
	},
	{
		"id": "buffalo_heavy_steps",
		"hero": HERO_BUFFALO,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Heavy steps",
		"description": "Every swing a little weightier.",
		# attack_damage is a multiplier on weapon.damage in CombatSystem
		# (base 1.0 — see scripts/logic/stat_system.gd's base_stats_for).
		# Flat additions stack BEFORE the percent multiplier, so a +4.0
		# flat would have made every Buffalo weapon hit 5x — clearly not
		# what "a little weightier" should mean. Use percent for parity
		# with the other attack-damage upgrades (sharper beak / wolfbreaker
		# / practiced arm), which are all percent-based.
		"modifiers": [
			{"stat": "attack_damage", "kind": "pct", "amount": 0.10},
		],
		"unlocks": [],
	},
	{
		"id": "buffalo_charge_practice",
		"hero": HERO_BUFFALO,
		"tier": 2,
		"prereq": "buffalo_thick_hide",
		"cost": 2,
		"display_name": "Charge practice",
		"description": "Buffalo's charge cooldown comes down with use. (Lands when the charge ability ships.)",
		"modifiers": [
			{"stat": "ability_cooldown", "kind": "pct", "amount": -0.20},
		],
		"unlocks": [],
	},
	{
		"id": "buffalo_braced_shoulders",
		"hero": HERO_BUFFALO,
		"tier": 3,
		"prereq": "buffalo_charge_practice",
		"cost": 3,
		"display_name": "Braced shoulders",
		"description": "The wolves bounce off. Big HP bump and a steadier swing.",
		"modifiers": [
			{"stat": "hp_max", "kind": "flat", "amount": 40.0},
			{"stat": "attack_speed", "kind": "pct", "amount": 0.10},
		],
		"unlocks": [],
	},

	# ── Goose — aggression / IGL ───────────────────────────────────
	{
		"id": "goose_quick_feet",
		"hero": HERO_GOOSE,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Quick feet",
		"description": "Goose moves faster across the watch.",
		"modifiers": [
			{"stat": "move_speed", "kind": "pct", "amount": 0.15},
		],
		"unlocks": [],
	},
	{
		"id": "goose_loud_call",
		"hero": HERO_GOOSE,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Loud call",
		"description": "Goose's dive cooldown shortens. (Lands when the dive ability ships.)",
		"modifiers": [
			{"stat": "ability_cooldown", "kind": "pct", "amount": -0.15},
		],
		"unlocks": [],
	},
	{
		"id": "goose_sharper_beak",
		"hero": HERO_GOOSE,
		"tier": 2,
		"prereq": "goose_loud_call",
		"cost": 2,
		"display_name": "Sharper beak",
		"description": "Each hit lands harder. Goose attack damage up.",
		"modifiers": [
			{"stat": "attack_damage", "kind": "pct", "amount": 0.18},
		],
		"unlocks": [],
	},
	{
		"id": "goose_skywatcher",
		"hero": HERO_GOOSE,
		"tier": 3,
		"prereq": "goose_sharper_beak",
		"cost": 3,
		"display_name": "Skywatcher",
		"description": "Goose's range and speed both come up. The line stays mobile.",
		"modifiers": [
			{"stat": "attack_range", "kind": "flat", "amount": 1.0},
			{"stat": "move_speed", "kind": "pct", "amount": 0.10},
		],
		"unlocks": [],
	},

	# ── Fox — initiator / recon ────────────────────────────────────
	{
		"id": "fox_light_paws",
		"hero": HERO_FOX,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Light paws",
		"description": "Fox slips through the woods quicker.",
		"modifiers": [
			{"stat": "move_speed", "kind": "pct", "amount": 0.18},
		],
		"unlocks": [],
	},
	{
		"id": "fox_keen_eyes",
		"hero": HERO_FOX,
		"tier": 1,
		"prereq": "",
		"cost": 1,
		"display_name": "Keen eyes",
		"description": "Fox gathers half again as fast.",
		"modifiers": [
			{"stat": "gather_speed", "kind": "pct", "amount": 0.20},
		],
		"unlocks": [],
	},
	{
		"id": "fox_cutpurse",
		"hero": HERO_FOX,
		"tier": 2,
		"prereq": "fox_keen_eyes",
		"cost": 2,
		"display_name": "Cutpurse",
		"description": "Snatch comes back to the hand sooner. (Lands when the snatch ability ships.)",
		"modifiers": [
			{"stat": "ability_cooldown", "kind": "pct", "amount": -0.20},
		],
		"unlocks": [],
	},
	{
		"id": "fox_wolfbreaker",
		"hero": HERO_FOX,
		"tier": 3,
		"prereq": "fox_cutpurse",
		"cost": 3,
		"display_name": "Wolfbreaker",
		"description": "Fox's strikes punch above their weight.",
		"modifiers": [
			{"stat": "attack_damage", "kind": "pct", "amount": 0.25},
		],
		"unlocks": [],
	},
]

# ── Lookups ──────────────────────────────────────────────────────────

static func by_id(id: String) -> Dictionary:
	for u in ALL:
		if String(u.id) == id:
			return u
	return {}

static func for_hero(hero_id: String) -> Array:
	# Returns shared + hero-specific upgrades. Shared first so the tree
	# UI can render Shared as a tab alongside the heroes.
	var out: Array = []
	for u in ALL:
		if String(u.hero) == HERO_SHARED or String(u.hero) == hero_id:
			out.append(u)
	return out

static func for_hero_only(hero_id: String) -> Array:
	# Strictly the hero's own upgrades (excludes Shared).
	var out: Array = []
	for u in ALL:
		if String(u.hero) == hero_id:
			out.append(u)
	return out

static func shared_upgrades() -> Array:
	var out: Array = []
	for u in ALL:
		if String(u.hero) == HERO_SHARED:
			out.append(u)
	return out

static func hero_tabs() -> Array:
	# Order matches the hero selector convention: Buffalo, Goose, Fox,
	# Shared. The lodge tree UI walks this list to lay out tabs.
	return [HERO_BUFFALO, HERO_GOOSE, HERO_FOX, HERO_SHARED]
