class_name RunEconomy extends RefCounted
##
## Embers earn-rate constants (BUF-149). Embers are the lodge meta-
## currency the player spends in the upgrade tree (BUF-148). Earn rates
## are tuned to produce ~5–10 embers per typical 30-min victory run;
## numbers are first-pass and meant to be retuned from telemetry once
## playtest data exists.
##
## Pure data — no scene-tree access. Economy logic lives in
## scripts/logic/stat_system.gd's award_embers().
##
## Naming note: this file is run_economy.gd (not economy.gd) because
## scripts/logic/economy.gd already exists for the wave-defense coin
## system that the survival rebuild left dormant. Renaming that file
## is a separate cleanup.

# Outcome rewards. Defeat earns less than victory, but never zero — a
# total wipe still produces *something* so the trip wasn't wasted.
const EMBERS_FOR_DEFEAT_BASE := 1
const EMBERS_FOR_VICTORY := 6

# Per-night-survived bonus (defeat path). 0 if you didn't even get to
# night 1; +1 per full night you survived. Caps at MAX_NIGHTS.
const EMBERS_PER_NIGHT_SURVIVED := 1

# Stretch bonuses. Wide thresholds because we're tuning post-playtest;
# these values produce ~5–10 embers/run today and are easy to nudge.
const EMBERS_BONUS_RESOURCES_THRESHOLD := 60   # gathered ≥ 60
const EMBERS_BONUS_RESOURCES_AMOUNT := 1
const EMBERS_BONUS_FELLED_THRESHOLD := 25      # felled ≥ 25
const EMBERS_BONUS_FELLED_AMOUNT := 1

static func award_for_run(outcome: String, nights_survived: int, resources_gathered: int, enemies_felled: int) -> int:
	# Pure tally — same inputs always produce the same embers count.
	# Caller persists the result via SaveIo.add_embers().
	var earned: int = 0
	if outcome == "victory":
		earned += EMBERS_FOR_VICTORY
	else:
		earned += EMBERS_FOR_DEFEAT_BASE
		earned += min(nights_survived, 3) * EMBERS_PER_NIGHT_SURVIVED
	if resources_gathered >= EMBERS_BONUS_RESOURCES_THRESHOLD:
		earned += EMBERS_BONUS_RESOURCES_AMOUNT
	if enemies_felled >= EMBERS_BONUS_FELLED_THRESHOLD:
		earned += EMBERS_BONUS_FELLED_AMOUNT
	return earned
