class_name DayNightData extends RefCounted
##
## Day/night cycle constants. Pure data — DayNightCycle (logic) reads
## these to drive its state machine. Adjusting balance happens here, not
## in the cycle code.
##
## A "run" is three full nights survived. Day 1 begins on DAY phase; the
## victory condition fires on the dawn AFTER the third night. Defeat
## fires whenever lodge HP or hero HP reaches 0, regardless of phase.
##
## Per-round prep (DAY) and night (NIGHT) durations live in
## `data/waves.gd` so the difficulty curve is tuned in one file (BUF-115).
## The constants below are fallbacks for callers that don't have a round
## index — and for DUSK/DAWN, which are fixed framing beats rather than
## per-round difficulty knobs.

const Waves := preload("res://data/waves.gd")

# Fallback day/night seconds — used when no round index is supplied
# (e.g. the HUD's pre-cycle initial value). Per-round overrides come
# from Waves.prep_seconds_for / night_seconds_for.
const DAY_SECONDS := 60.0
const DUSK_SECONDS := 5.0
const NIGHT_SECONDS := 35.0
const DAWN_SECONDS := 5.0

const MAX_NIGHTS := 3

# Phase enum mirrored as constants so adapters can match without importing
# the logic class. Keep these in lock-step with DayNightCycle.Phase.
const PHASE_DAY := 0
const PHASE_DUSK := 1
const PHASE_NIGHT := 2
const PHASE_DAWN := 3

const PHASE_NAMES := {
	PHASE_DAY: "day",
	PHASE_DUSK: "dusk",
	PHASE_NIGHT: "night",
	PHASE_DAWN: "dawn",
}

static func duration_for(phase: int, round_index: int = 0) -> float:
	# round_index = 0 means "no round context" — return the fallback.
	# Real callers should pass the upcoming round so per-round tuning
	# in data/waves.gd applies.
	match phase:
		PHASE_DAY:
			return Waves.prep_seconds_for(round_index) if round_index > 0 else DAY_SECONDS
		PHASE_DUSK:
			return DUSK_SECONDS
		PHASE_NIGHT:
			return Waves.night_seconds_for(round_index) if round_index > 0 else NIGHT_SECONDS
		PHASE_DAWN:
			return DAWN_SECONDS
		_:
			return 0.0

static func phase_name(phase: int) -> String:
	return PHASE_NAMES.get(phase, "unknown")
