class_name DayNightData extends RefCounted
##
## Day/night cycle constants. Pure data — DayNightCycle (logic) reads
## these to drive its state machine. Adjusting balance happens here, not
## in the cycle code.
##
## A "run" is three full nights survived. Day 1 begins on DAY phase; the
## victory condition fires on the dawn AFTER the third night. Defeat
## fires whenever lodge HP or hero HP reaches 0, regardless of phase.

const DAY_SECONDS := 60.0
const DUSK_SECONDS := 5.0
const NIGHT_SECONDS := 30.0
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

static func duration_for(phase: int) -> float:
	match phase:
		PHASE_DAY: return DAY_SECONDS
		PHASE_DUSK: return DUSK_SECONDS
		PHASE_NIGHT: return NIGHT_SECONDS
		PHASE_DAWN: return DAWN_SECONDS
		_: return 0.0

static func phase_name(phase: int) -> String:
	return PHASE_NAMES.get(phase, "unknown")
