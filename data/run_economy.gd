class_name RunEconomy extends RefCounted
##
## Embers earn-rate constants (BUF-149). Embers are the lodge meta-
## currency the player spends in the upgrade tree (BUF-148). Earn rates
## are tuned to produce ~5–10 embers per typical 30-min victory run;
## numbers are first-pass and meant to be retuned from telemetry once
## playtest data exists.
##
## Pure data — no scene-tree access. Economy logic lives in
## scripts/adapters/run_lifecycle.gd's _award_embers(); the call site
## resolves the artifact-novelty + first-hero-run flags from save state
## before invoking award_for_run().
##
## Naming note: this file is run_economy.gd (not economy.gd) because
## scripts/logic/economy.gd already exists for the wave-defense coin
## system that the survival rebuild left dormant. Renaming that file
## is a separate cleanup.
##
## Reward shape (issue spec):
##   • 1 ember per night survived (capped at MAX_NIGHTS so a future
##     longer cycle doesn't silently inflate rewards)
##   • +2 embers on victory (the 3-night clear)
##   • +1 ember when the run leaves a lodge artifact never seen before
##     (BUF-130 guarantees an artifact every run; the reward is for
##     *novelty*, not the draw itself, so duplicate artifacts don't
##     pad the wallet)
##   • +1 ember the first time a hero is taken on a run (cheap "try
##     them out" hook; once per hero across the campaign)
##
## A 3-night victory with a fresh artifact + first-hero bonus tallies
## 3 + 2 + 1 + 1 = 7 embers — comfortably inside the 5–10 target band
## without any defeat-path stretch goals (those were the resources /
## felled thresholds; replaced by the spec's artifact + hero levers).

const DayNight := preload("res://data/day_night.gd")

# Per-night reward, applied to BOTH outcomes. Capped at MAX_NIGHTS so
# the math doesn't drift when day_night.MAX_NIGHTS changes; a longer
# cycle would pay out more nights but still respects the cap.
const EMBERS_PER_NIGHT_SURVIVED := 1

# Victory bonus on top of nights-survived. Pays for the 3-night clear
# being the design goal; defeat earns the per-night reward only.
const EMBERS_VICTORY_BONUS := 2

# Per-discovery bonus. Awarded when the artifact left behind has never
# been seen on this save before. Naturally trends to zero once the pool
# (~30 entries in lodge_artifacts.gd) is exhausted, which is fine —
# upgrade purchases scale with the early-campaign's larger ember intake.
const EMBERS_NEW_ARTIFACT := 1

# Per-hero "try them out" bonus. Once-per-hero, paid the first time a
# run is recorded for that hero on this save. Three heroes × 1 ember =
# +3 embers max from this lever across the whole campaign.
const EMBERS_FIRST_HERO_RUN := 1

static func award_for_run(
	outcome: String,
	nights_survived: int,
	artifact_is_new: bool,
	first_hero_run: bool,
) -> int:
	# Pure tally — same inputs always produce the same embers count.
	# Caller persists the result via SaveIo.add_embers().
	#
	# nights_survived is clamped to MAX_NIGHTS rather than left
	# unbounded so a future longer cycle doesn't quietly inflate the
	# economy. Negative inputs collapse to 0 (defensive — should never
	# happen, the lifecycle adapter only counts up).
	var nights: int = clamp(nights_survived, 0, DayNight.MAX_NIGHTS)
	var earned: int = nights * EMBERS_PER_NIGHT_SURVIVED
	if outcome == "victory":
		earned += EMBERS_VICTORY_BONUS
	if artifact_is_new:
		earned += EMBERS_NEW_ARTIFACT
	if first_hero_run:
		earned += EMBERS_FIRST_HERO_RUN
	return earned
