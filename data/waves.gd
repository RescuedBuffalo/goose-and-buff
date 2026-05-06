class_name WavesData extends RefCounted
##
## Wave compositions per night. Each round picks a named *archetype*
## (Probe / Rush / Skirmish / Siege) so the three-night arc has
## mechanical variety instead of "more wolves, faster". Night 3 always
## resolves to SIEGE, which always includes the AlphaWolf mini-boss.
##
## BUF-115: this file is also the canonical home for per-round *timing*
## (prep / night seconds) and per-round *enemy stat scale* (HP and damage
## multipliers applied to the base enemies.gd stats). Tuning the run
## difficulty curve happens here, not in DayNightCycle and not in the
## enemy adapter — keeping every knob in one place is the whole point.
##
## Schema for a returned composition:
##   {
##     "index":          int,                  # 1-indexed round/night
##     "name":           "Second night",       # body-text label
##     "archetype":      "RUSH",               # ALL-CAPS id
##     "archetype_name": "Rush",               # sentence-case label
##     "banner":         "RUSH",               # ALL-CAPS shout for HUD
##     "has_mini_boss":  bool,
##     "enemies":        [{ type, count, spawn_interval }, ...],
##     "stat_scale":     { "hp": 1.0, "damage": 1.0 },
##     "prep_seconds":   60.0,                 # DAY-phase length for this round
##     "night_seconds":  35.0,                 # NIGHT-phase length for this round
##   }
##
## Archetypes are kept declarative — adjusting balance happens here, not
## in WaveDirector. The director just drains the spawn queue.

# ── Archetypes ────────────────────────────────────────────────────────
#
# `banner` is the ALL-CAPS shout the HUD writes across the screen on
# wave start (voice rule: shouts are caps, body text is sentence case).
# SIEGE leans on the issue's "A BIG ONE INCOMING" example because the
# mini-boss is what the moment is selling.

const ARCHETYPE_PROBE := {
	"id": "PROBE",
	"name": "Probe",
	"banner": "PROBE",
	"has_mini_boss": false,
	"enemies": [
		{"type": "FrostWolf", "count": 6, "spawn_interval": 2.5},
	],
}

const ARCHETYPE_RUSH := {
	"id": "RUSH",
	"name": "Rush",
	"banner": "RUSH",
	"has_mini_boss": false,
	"enemies": [
		{"type": "DireWolf", "count": 12, "spawn_interval": 1.2},
	],
}

const ARCHETYPE_SKIRMISH := {
	"id": "SKIRMISH",
	"name": "Skirmish",
	"banner": "SKIRMISH",
	"has_mini_boss": false,
	"enemies": [
		{"type": "FrostWolf", "count": 4, "spawn_interval": 2.0},
		{"type": "FrostStalker", "count": 5, "spawn_interval": 2.4},
	],
}

# Mini-boss night. The pack lands first and the AlphaWolf trails on a
# longer interval so the boss is the climax, not the opener.
const ARCHETYPE_SIEGE := {
	"id": "SIEGE",
	"name": "Siege",
	"banner": "A BIG ONE INCOMING",
	"has_mini_boss": true,
	"enemies": [
		{"type": "FrostWolf", "count": 6, "spawn_interval": 1.8},
		{"type": "DireWolf", "count": 3, "spawn_interval": 2.0},
		{"type": "AlphaWolf", "count": 1, "spawn_interval": 6.0},
	],
}

const ARCHETYPES := {
	"PROBE": ARCHETYPE_PROBE,
	"RUSH": ARCHETYPE_RUSH,
	"SKIRMISH": ARCHETYPE_SKIRMISH,
	"SIEGE": ARCHETYPE_SIEGE,
}

# ── Round plan ────────────────────────────────────────────────────────
#
# Round 1 is always PROBE — gentle on-ramp, teaches the swing arc.
# Round 2 picks from {RUSH, SKIRMISH} so the night-2 shape varies run
# to run (escalation in *kind*, not just *count*). Round 3 is always
# SIEGE so the mini-boss guarantee from BUF-114 holds.
#
# A round with multiple options is rolled at start_wave time. Single-
# option rounds short-circuit the RNG so deterministic playtests stay
# deterministic for rounds 1 and 3.

const ROUND_PLAN := {
	1: ["PROBE"],
	2: ["RUSH", "SKIRMISH"],
	3: ["SIEGE"],
}

const TOTAL_ROUNDS := 3

# Display names per round — body-text label, sentence case.
const ROUND_NAMES := {
	1: "First night",
	2: "Second night",
	3: "Third night",
}

# ── Run-shape tunables (BUF-115) ──────────────────────────────────────
#
# Per-round prep + night durations build the difficulty arc. Round 1 is
# short and forgiving so the on-ramp doesn't drag. Round 2 stretches the
# day so the player has time to react to the mid-run threat shift. Round
# 3 gets the longest prep (recover from Night 2, brace for siege) and
# the longest night (the mini-boss needs time to land).
#
# A full run with these defaults runs ~7:30 (within the 7-12 minute
# target). Numbers are intentionally first-pass — re-tune after the
# first M2 playtest. DUSK and DAWN are fixed in day_night.gd because
# they're framing beats, not difficulty knobs.
const ROUND_PREP_SECONDS := {
	1: 60.0,
	2: 90.0,
	3: 120.0,
}

const ROUND_NIGHT_SECONDS := {
	1: 35.0,
	2: 50.0,
	3: 60.0,
}

# Per-round multipliers applied to base enemy stats from enemies.gd. The
# wave already escalates in *kind* (PROBE → RUSH/SKIRMISH → SIEGE); this
# layers a gentle stat ramp on top so an individual wolf on Night 3 hits
# harder than the same wolf on Night 1. Keep multipliers conservative —
# big jumps make the arc feel arbitrary rather than earned.
const ROUND_STAT_SCALE := {
	1: {"hp": 1.0, "damage": 1.0},
	2: {"hp": 1.10, "damage": 1.05},
	3: {"hp": 1.25, "damage": 1.15},
}

# ── API ──────────────────────────────────────────────────────────────

static func for_round(round_index: int, rng: RandomNumberGenerator = null) -> Dictionary:
	# Rounds (nights) are 1-indexed in design language. Out-of-range
	# rounds clamp to the last entry — same defensive shape the wave
	# director relied on before BUF-114.
	#
	# Optional seeded RNG (BUF-151). When supplied, archetype rolls use
	# it instead of the engine global so multiplayer peers running their
	# own wave_director.tick produce identical compositions. Old solo
	# callers can still call without an rng — falls back to randi().
	var idx: int = clamp(round_index, 1, TOTAL_ROUNDS)
	var pool: Array = ROUND_PLAN.get(idx, ["PROBE"])
	var archetype_id: String = pool[0]
	if pool.size() > 1:
		if rng != null:
			archetype_id = String(pool[rng.randi_range(0, pool.size() - 1)])
		else:
			archetype_id = String(pool[randi() % pool.size()])
	return _composition_for(idx, archetype_id)

static func for_round_with_archetype(round_index: int, archetype_id: String) -> Dictionary:
	# Test / debug entry point — pin a specific archetype regardless
	# of the round plan. Useful when iterating on Skirmish balance
	# without re-rolling night 2 ten times.
	var idx: int = clamp(round_index, 1, TOTAL_ROUNDS)
	var id: String = archetype_id if ARCHETYPES.has(archetype_id) else "PROBE"
	return _composition_for(idx, id)

static func prep_seconds_for(round_index: int) -> float:
	var idx: int = clamp(round_index, 1, TOTAL_ROUNDS)
	return float(ROUND_PREP_SECONDS.get(idx, ROUND_PREP_SECONDS[TOTAL_ROUNDS]))

static func night_seconds_for(round_index: int) -> float:
	var idx: int = clamp(round_index, 1, TOTAL_ROUNDS)
	return float(ROUND_NIGHT_SECONDS.get(idx, ROUND_NIGHT_SECONDS[TOTAL_ROUNDS]))

static func stat_scale_for(round_index: int) -> Dictionary:
	var idx: int = clamp(round_index, 1, TOTAL_ROUNDS)
	# Return a fresh copy so callers can't accidentally mutate the const.
	var scale: Dictionary = ROUND_STAT_SCALE.get(idx, {"hp": 1.0, "damage": 1.0})
	return {"hp": float(scale.get("hp", 1.0)), "damage": float(scale.get("damage", 1.0))}

static func _composition_for(idx: int, archetype_id: String) -> Dictionary:
	var arch: Dictionary = ARCHETYPES[archetype_id]
	return {
		"index": idx,
		"name": ROUND_NAMES.get(idx, "Night %d" % idx),
		"archetype": archetype_id,
		"archetype_name": arch.name,
		"banner": arch.banner,
		"has_mini_boss": arch.has_mini_boss,
		"enemies": arch.enemies,
		"stat_scale": stat_scale_for(idx),
		"prep_seconds": prep_seconds_for(idx),
		"night_seconds": night_seconds_for(idx),
	}
