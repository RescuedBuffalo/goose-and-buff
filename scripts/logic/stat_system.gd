class_name StatSystem extends RefCounted
##
## Pure stat resolver (BUF-147). Given a hero_id and a list of owned
## upgrade ids, returns an `effective_stats` dict the gameplay systems
## consume — combat reads attack_damage / attack_speed / attack_range,
## hero reads hp_max / move_speed, gather reads gather_speed, etc.
##
## Composition order is FLAT FIRST, THEN PERCENT. So a +10 hp flat then
## a +50% pct yields (base + 10) × 1.5 — predictable and the only order
## documented to gameplay code, so balance numbers stay honest.
##
## Caching: effective_stats is recomputed only when owned_upgrades
## changes (typically between runs at the lodge). Don't recompute per
## frame.
##
## Closed enumeration (intentionally small for M2):
##   hp_max, attack_damage, attack_speed, attack_range, gather_speed,
##   build_speed, move_speed, ability_cooldown, lodge_hp_max,
##   inventory_slots
##
## If a future upgrade wants a stat outside this set, FLAG IT before
## adding — most "new stats" are actually a multiplier on an existing
## stat or a feature gate, not a stat. The brief in M2's prompt is
## explicit about this.

const Upgrades := preload("res://data/upgrades.gd")
const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")

const STATS := [
	"hp_max", "attack_damage", "attack_speed", "attack_range",
	"gather_speed", "build_speed", "move_speed", "ability_cooldown",
	"lodge_hp_max", "inventory_slots",
]

# ── Public API ────────────────────────────────────────────────────────

static func base_stats_for(hero_id: String) -> Dictionary:
	# Per-hero base values pulled from the canonical heroes.gd table
	# plus the survival rebuild's gameplay constants. Anything not
	# rooted here ends up being magic-numbered in adapters, so we
	# centralize.
	var hero: Dictionary = Heroes.ALL.get(hero_id, Heroes.Buffalo)
	var sig_cooldown: float = float(hero.get("signatureCooldown", 6.0))
	return {
		"hp_max": float(hero.get("baseHealth", 100)),
		"attack_damage": 1.0,           # weapon-relative multiplier
		"attack_speed": 1.0,            # 1.0 = base cooldown; >1 = faster
		"attack_range": 0.0,            # flat tiles added to weapon range
		"gather_speed": 1.0,            # 1.0 = base rate
		"build_speed": 1.0,             # reserved; not yet plumbed
		"move_speed": float(hero.get("moveSpeed", 12)),
		"ability_cooldown": sig_cooldown,
		"lodge_hp_max": Sectors.CORE_HEALTH,
		"inventory_slots": 8.0,         # InventorySystem.SLOT_COUNT
	}

static func effective_stats(hero_id: String, owned_upgrades: Array) -> Dictionary:
	# Pure: identical inputs → identical outputs. Owned-upgrade order
	# does not matter (commutative across both flat and pct buckets
	# because we sum each bucket independently).
	var stats: Dictionary = base_stats_for(hero_id).duplicate()
	# Bucket modifiers by stat first so we apply flat-then-pct
	# deterministically per stat.
	var flat_by_stat: Dictionary = {}
	var pct_by_stat: Dictionary = {}
	for stat in STATS:
		flat_by_stat[stat] = 0.0
		pct_by_stat[stat] = 0.0
	for owned_id in owned_upgrades:
		var upgrade: Dictionary = Upgrades.by_id(String(owned_id))
		if upgrade.is_empty():
			continue
		# Skip cross-hero upgrades that don't apply to this hero. Shared
		# always applies; hero-specific only when matching.
		var owner_hero: String = String(upgrade.get("hero", "Shared"))
		if owner_hero != Upgrades.HERO_SHARED and owner_hero != hero_id:
			continue
		for mod in upgrade.get("modifiers", []):
			var stat: String = String(mod.get("stat", ""))
			if not flat_by_stat.has(stat):
				push_warning("StatSystem: upgrade '%s' references unknown stat '%s' — ignoring" % [owned_id, stat])
				continue
			var amt: float = float(mod.get("amount", 0.0))
			if String(mod.get("kind", "flat")) == "pct":
				pct_by_stat[stat] = float(pct_by_stat[stat]) + amt
			else:
				flat_by_stat[stat] = float(flat_by_stat[stat]) + amt
	# Compose: flat first, then percent.
	for stat in STATS:
		var v: float = float(stats[stat]) + float(flat_by_stat[stat])
		v = v * (1.0 + float(pct_by_stat[stat]))
		stats[stat] = v
	return stats

static func unlocks_from(owned_upgrades: Array) -> Dictionary:
	# Returns {item_id: true} for every item / weapon unlocked by the
	# owned upgrade set. Lodge UI uses this to display "available at the
	# lodge"; main.gd consumes it at run-start to seed starter inventory.
	var out: Dictionary = {}
	for owned_id in owned_upgrades:
		var upgrade: Dictionary = Upgrades.by_id(String(owned_id))
		for u in upgrade.get("unlocks", []):
			out[String(u)] = true
	return out

# ── Purchase model ────────────────────────────────────────────────────
##
## Pure: returns the new {embers, owned_upgrades} pair plus an outcome.
## Caller persists via SaveIo.

const REASON_OK := "ok"
const REASON_UNKNOWN := "unknown_upgrade"
const REASON_ALREADY_OWNED := "already_owned"
const REASON_NO_PREREQ := "no_prereq"
const REASON_INSUFFICIENT := "insufficient_embers"

static func can_purchase(upgrade_id: String, embers: int, owned_upgrades: Array) -> Dictionary:
	var upgrade: Dictionary = Upgrades.by_id(upgrade_id)
	if upgrade.is_empty():
		return {"ok": false, "reason": REASON_UNKNOWN}
	if owned_upgrades.has(upgrade_id):
		return {"ok": false, "reason": REASON_ALREADY_OWNED}
	var prereq: String = String(upgrade.get("prereq", ""))
	if not prereq.is_empty() and not owned_upgrades.has(prereq):
		return {"ok": false, "reason": REASON_NO_PREREQ}
	if int(upgrade.get("cost", 0)) > embers:
		return {"ok": false, "reason": REASON_INSUFFICIENT}
	return {"ok": true, "reason": REASON_OK}

static func apply_purchase(upgrade_id: String, embers: int, owned_upgrades: Array) -> Dictionary:
	# Returns {ok, embers, owned_upgrades, reason}. On failure, the
	# previous (embers, owned_upgrades) pass through unchanged so callers
	# can use the result as the new authoritative state regardless.
	var check: Dictionary = can_purchase(upgrade_id, embers, owned_upgrades)
	if not check.ok:
		return {
			"ok": false,
			"embers": embers,
			"owned_upgrades": owned_upgrades.duplicate(),
			"reason": check.reason,
		}
	var upgrade: Dictionary = Upgrades.by_id(upgrade_id)
	var new_owned: Array = owned_upgrades.duplicate()
	new_owned.append(upgrade_id)
	return {
		"ok": true,
		"embers": embers - int(upgrade.cost),
		"owned_upgrades": new_owned,
		"reason": REASON_OK,
	}
