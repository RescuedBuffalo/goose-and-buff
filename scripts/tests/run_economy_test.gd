class_name RunEconomyTest extends RefCounted
##
## Scratch tests for RunEconomy.award_for_run + the SaveState history
## helpers added for BUF-149's artifact-novelty + first-hero-run bonuses.
##
## Same shape as stat_system_test.gd / world_generator_test.gd — no test
## framework, just static closures that print PASS/FAIL. F12 in
## debug_overlay.gd runs all three suites together.
##
## Cases cover:
##   1. Defeat at zero nights with a duplicate artifact and no hero
##      novelty → 0 embers (the design floor: a wipe with nothing new
##      really does pay nothing — by design, replacing the previous
##      "always +1 floor" with a tighter spec).
##   2. Per-night reward applies to defeat (not just victory).
##   3. Per-night reward caps at MAX_NIGHTS so a longer cycle in
##      data/day_night.gd doesn't silently inflate rewards.
##   4. Victory bonus stacks on top of nights-survived.
##   5. New-artifact bonus only fires when artifact_is_new is true.
##   6. First-hero bonus only fires when first_hero_run is true.
##   7. The full-stack 3-night victory + new artifact + first hero lands
##      in the issue's 5–10 ember target band (locks the math against
##      a future tweak that drifts the headline number).
##   8. has_run_with_hero and has_artifact_with_id walk the in-memory
##      save dict correctly (true match, false miss, malformed entries
##      ignored without crashing).

const RunEconomyClass := preload("res://data/run_economy.gd")
const SaveStateClass := preload("res://scripts/logic/save_state.gd")
const DayNight := preload("res://data/day_night.gd")

static func run_all() -> Dictionary:
	var results: Array = []
	var passed: int = 0
	var failed: int = 0
	var cases: Array = [
		_case_zero_nights_no_bonuses,
		_case_per_night_reward_on_defeat,
		_case_per_night_reward_capped,
		_case_victory_bonus_stacks,
		_case_new_artifact_bonus,
		_case_first_hero_bonus,
		_case_full_stack_in_target_band,
		_case_has_run_with_hero,
		_case_has_artifact_with_id,
	]
	for c in cases:
		var r: Dictionary = c.call()
		results.append(r.line)
		if bool(r.ok):
			passed += 1
		else:
			failed += 1
	return {"passed": passed, "failed": failed, "results": results}

static func print_results(report: Dictionary) -> void:
	print("── RunEconomy + history-helper test ─────────────────")
	for line in report.results:
		print(line)
	print("── %d passed, %d failed" % [int(report.passed), int(report.failed)])

# ── Cases ────────────────────────────────────────────────────────────

static func _case_zero_nights_no_bonuses() -> Dictionary:
	# Defeat, 0 nights, duplicate artifact, returning hero → 0 embers.
	# This is the harshest path; design is intentionally tight here so
	# the bonus levers carry weight elsewhere.
	var got: int = RunEconomyClass.award_for_run("defeat", 0, false, false)
	if got != 0:
		return _fail("zero nights, no bonuses", "got %d want 0" % got)
	return _pass("zero nights, no bonuses → 0")

static func _case_per_night_reward_on_defeat() -> Dictionary:
	# 2-night defeat: 2 nights × 1 = 2 embers. No victory bonus, no
	# artifact, no first hero.
	var got: int = RunEconomyClass.award_for_run("defeat", 2, false, false)
	if got != 2:
		return _fail("per-night on defeat", "got %d want 2" % got)
	return _pass("per-night on defeat → 2")

static func _case_per_night_reward_capped() -> Dictionary:
	# Surviving more nights than the cap shouldn't pay extra. We pass
	# MAX_NIGHTS+5 to ensure the clamp holds; victory adds the bonus.
	var got: int = RunEconomyClass.award_for_run(
		"victory", DayNight.MAX_NIGHTS + 5, false, false,
	)
	var want: int = DayNight.MAX_NIGHTS + 2
	if got != want:
		return _fail("per-night cap", "got %d want %d (cap+victory)" % [got, want])
	return _pass("per-night caps at MAX_NIGHTS")

static func _case_victory_bonus_stacks() -> Dictionary:
	# 3-night victory, no other bonuses: 3 × 1 + 2 = 5.
	var got: int = RunEconomyClass.award_for_run("victory", 3, false, false)
	if got != 5:
		return _fail("victory bonus stacks", "got %d want 5" % got)
	return _pass("victory bonus stacks")

static func _case_new_artifact_bonus() -> Dictionary:
	# 1-night defeat + new artifact: 1 + 1 = 2.
	var got_new: int = RunEconomyClass.award_for_run("defeat", 1, true, false)
	if got_new != 2:
		return _fail("new artifact bonus", "got %d want 2" % got_new)
	# Same scenario without novelty stays at 1.
	var got_dup: int = RunEconomyClass.award_for_run("defeat", 1, false, false)
	if got_dup != 1:
		return _fail("new artifact bonus (negative)", "duplicate paid %d want 1" % got_dup)
	return _pass("new artifact bonus only on novelty")

static func _case_first_hero_bonus() -> Dictionary:
	# 0-night defeat + first hero run: 0 + 1 = 1.
	var got_first: int = RunEconomyClass.award_for_run("defeat", 0, false, true)
	if got_first != 1:
		return _fail("first-hero bonus", "got %d want 1" % got_first)
	# Same scenario without first-hero stays at 0.
	var got_returning: int = RunEconomyClass.award_for_run("defeat", 0, false, false)
	if got_returning != 0:
		return _fail("first-hero bonus (negative)", "returning hero paid %d want 0" % got_returning)
	return _pass("first-hero bonus only on novelty")

static func _case_full_stack_in_target_band() -> Dictionary:
	# 3-night victory + new artifact + first hero: 3 + 2 + 1 + 1 = 7.
	# Lock the math against drift — the issue's 5–10 target band breaks
	# if any constant shifts without a matching documentation update.
	var got: int = RunEconomyClass.award_for_run("victory", 3, true, true)
	if got != 7:
		return _fail("full-stack victory", "got %d want 7" % got)
	if got < 5 or got > 10:
		return _fail("full-stack victory band", "got %d outside 5..10" % got)
	return _pass("full-stack victory in 5–10 band")

static func _case_has_run_with_hero() -> Dictionary:
	var state: Dictionary = SaveStateClass.empty()
	# Empty save: no hero matches.
	if SaveStateClass.has_run_with_hero(state, "Buffalo"):
		return _fail("has_run_with_hero empty", "matched Buffalo on empty state")
	# Append a Buffalo run; should match Buffalo, miss Goose.
	var record := SaveStateClass.make_run_record("Buffalo", "victory", 3, 0, 0, 0.0, 0)
	state = SaveStateClass.append_run(state, record)
	if not SaveStateClass.has_run_with_hero(state, "Buffalo"):
		return _fail("has_run_with_hero positive", "missed Buffalo after append")
	if SaveStateClass.has_run_with_hero(state, "Goose"):
		return _fail("has_run_with_hero negative", "matched Goose on Buffalo-only history")
	# Malformed entry shouldn't crash — append a non-dict and re-query.
	var corrupted: Dictionary = state.duplicate(true)
	(corrupted["runs"] as Array).append("not a dict")
	if not SaveStateClass.has_run_with_hero(corrupted, "Buffalo"):
		return _fail("has_run_with_hero malformed-skip", "malformed entry broke positive case")
	return _pass("has_run_with_hero")

static func _case_has_artifact_with_id() -> Dictionary:
	var state: Dictionary = SaveStateClass.empty()
	if SaveStateClass.has_artifact_with_id(state, "iron_key"):
		return _fail("has_artifact_with_id empty", "matched iron_key on empty state")
	# Empty id is treated as "no match" — guard for the "" return from
	# draw_lodge_artifact when the pool is empty.
	if SaveStateClass.has_artifact_with_id(state, ""):
		return _fail("has_artifact_with_id empty id", "empty id matched")
	# Append + match.
	var artifact := SaveStateClass.make_artifact_record("iron_key", "victory", 0)
	state = SaveStateClass.append_artifact(state, artifact)
	if not SaveStateClass.has_artifact_with_id(state, "iron_key"):
		return _fail("has_artifact_with_id positive", "missed iron_key after append")
	if SaveStateClass.has_artifact_with_id(state, "river_stone"):
		return _fail("has_artifact_with_id negative", "matched river_stone on iron-only history")
	return _pass("has_artifact_with_id")

# ── Helpers ──────────────────────────────────────────────────────────

static func _pass(label: String) -> Dictionary:
	return {"ok": true, "line": "  PASS  " + label}

static func _fail(label: String, detail: String) -> Dictionary:
	return {"ok": false, "line": "  FAIL  %s — %s" % [label, detail]}
