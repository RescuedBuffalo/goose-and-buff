class_name StatSystemTest extends RefCounted
##
## Scratch composition test for StatSystem (BUF-147 acceptance criterion:
## "Unit-style test (or scratch script) verifies modifier composition").
##
## Not a real test framework — Godot has no first-party one and bringing
## in gut/gd-unit for a single ticket is overkill. Instead, run_all() walks
## a list of fixed scenarios, asserts the expected post-composition stat,
## and prints a pass/fail line per case. main.gd binds F12 to run it so
## the dev can invoke from the running game; CI is out of scope for M2.
##
## Cases cover:
##   1. No upgrades → base stats (sanity)
##   2. Single flat upgrade
##   3. Single percent upgrade
##   4. Flat + percent on same stat — order is FLAT FIRST, THEN PERCENT
##   5. Hero-scoped upgrade ignored when wrong hero is active
##   6. Cross-hero stacking (Shared upgrade on Buffalo applies)
##   7. Unknown upgrade id → silently ignored
##   8. apply_purchase respects prereqs + cost
##
## Each scenario is a closure: setup → expected → check. Output is a
## simple line per case so the dev can scan results in the Output panel.

const StatSystem := preload("res://scripts/logic/stat_system.gd")

const EPSILON := 0.001

static func run_all() -> Dictionary:
	# Returns {passed, failed, results: Array[String]} so callers can either
	# print or surface in a UI. main.gd just prints to console.
	var results: Array = []
	var passed: int = 0
	var failed: int = 0
	var cases: Array = [
		_case_no_upgrades_returns_base,
		_case_single_flat,
		_case_single_pct,
		_case_flat_then_pct,
		_case_two_flats_compose,
		_case_two_pcts_compose,
		_case_hero_scoping_ignores_wrong_hero,
		_case_shared_applies_across_heroes,
		_case_unknown_id_ignored,
		_case_apply_purchase_blocks_unknown,
		_case_apply_purchase_blocks_already_owned,
		_case_apply_purchase_blocks_missing_prereq,
		_case_apply_purchase_blocks_insufficient,
		_case_apply_purchase_succeeds,
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
	# Convenience: prefix with a marker line so the test output is easy to
	# eyeball amid the rest of the engine's logs.
	print("── StatSystem composition test ──────────────────────")
	for line in report.results:
		print(line)
	print("── %d passed, %d failed" % [int(report.passed), int(report.failed)])

# ── Cases ────────────────────────────────────────────────────────────

static func _case_no_upgrades_returns_base() -> Dictionary:
	var stats: Dictionary = StatSystem.effective_stats("Buffalo", [])
	var base: Dictionary = StatSystem.base_stats_for("Buffalo")
	for k in StatSystem.STATS:
		if abs(float(stats[k]) - float(base[k])) > EPSILON:
			return _fail("no upgrades returns base", "stat %s drifted: got %f want %f" % [k, stats[k], base[k]])
	return _pass("no upgrades returns base")

static func _case_single_flat() -> Dictionary:
	# shared_warm_cloak: hp_max +20 flat. Buffalo base hp_max = 160.
	var stats: Dictionary = StatSystem.effective_stats("Buffalo", ["shared_warm_cloak"])
	var got: float = float(stats.hp_max)
	if abs(got - 180.0) > EPSILON:
		return _fail("single flat upgrade", "hp_max got %f want 180" % got)
	return _pass("single flat upgrade")

static func _case_single_pct() -> Dictionary:
	# shared_quick_hands: gather_speed +0.15 pct. Base gather_speed = 1.0.
	var stats: Dictionary = StatSystem.effective_stats("Buffalo", ["shared_quick_hands"])
	var got: float = float(stats.gather_speed)
	if abs(got - 1.15) > EPSILON:
		return _fail("single pct upgrade", "gather_speed got %f want 1.15" % got)
	return _pass("single pct upgrade")

static func _case_flat_then_pct() -> Dictionary:
	# shared_warm_cloak (+20 flat) + buffalo_thick_hide (+15% pct) on
	# Buffalo. Base hp_max = 160. Expected: (160 + 20) * 1.15 = 207.
	# Order matters — pct first would yield 160 * 1.15 + 20 = 204, which
	# violates the documented composition order (flat then pct).
	var stats: Dictionary = StatSystem.effective_stats(
		"Buffalo", ["shared_warm_cloak", "buffalo_thick_hide"],
	)
	var got: float = float(stats.hp_max)
	if abs(got - 207.0) > EPSILON:
		return _fail("flat then pct order", "hp_max got %f want 207 (flat first then pct)" % got)
	return _pass("flat then pct order")

static func _case_two_flats_compose() -> Dictionary:
	# shared_warm_cloak (+20) + buffalo_braced_shoulders (+40 flat hp).
	# Base 160 + 20 + 40 = 220, then attack_speed pct from braced_shoulders
	# is on a different stat so doesn't touch hp.
	var stats: Dictionary = StatSystem.effective_stats(
		"Buffalo", ["shared_warm_cloak", "buffalo_braced_shoulders"],
	)
	var got: float = float(stats.hp_max)
	if abs(got - 220.0) > EPSILON:
		return _fail("two flats compose", "hp_max got %f want 220" % got)
	return _pass("two flats compose")

static func _case_two_pcts_compose() -> Dictionary:
	# Two pct on the same stat add (not multiply): goose_quick_feet
	# (+0.15) and goose_skywatcher's move_speed (+0.10). Total +0.25 on
	# Goose's base move_speed of 18 → 18 * 1.25 = 22.5.
	var stats: Dictionary = StatSystem.effective_stats(
		"Goose", ["goose_quick_feet", "goose_sharper_beak", "goose_skywatcher"],
	)
	# skywatcher requires sharper_beak as prereq; we include it so the
	# upgrade list is logically valid even though the test doesn't exercise
	# the prereq check itself.
	var got: float = float(stats.move_speed)
	if abs(got - 22.5) > EPSILON:
		return _fail("two pcts compose (additive)", "move_speed got %f want 22.5" % got)
	return _pass("two pcts compose (additive)")

static func _case_hero_scoping_ignores_wrong_hero() -> Dictionary:
	# buffalo_thick_hide is hero-scoped to Buffalo. Applying it to Goose
	# must NOT modify Goose's hp_max.
	var stats: Dictionary = StatSystem.effective_stats("Goose", ["buffalo_thick_hide"])
	var base: Dictionary = StatSystem.base_stats_for("Goose")
	if abs(float(stats.hp_max) - float(base.hp_max)) > EPSILON:
		return _fail("hero scoping (wrong hero)", "hp_max drifted: got %f want %f" % [stats.hp_max, base.hp_max])
	return _pass("hero scoping (wrong hero)")

static func _case_shared_applies_across_heroes() -> Dictionary:
	# A Shared upgrade should apply regardless of active hero.
	var fox_with: Dictionary = StatSystem.effective_stats("Fox", ["shared_warm_cloak"])
	var fox_base: Dictionary = StatSystem.base_stats_for("Fox")
	if abs(float(fox_with.hp_max) - (float(fox_base.hp_max) + 20.0)) > EPSILON:
		return _fail("shared applies across heroes", "Fox hp_max got %f want %f" % [fox_with.hp_max, fox_base.hp_max + 20.0])
	return _pass("shared applies across heroes")

static func _case_unknown_id_ignored() -> Dictionary:
	# Garbage id should not crash and should not modify base stats.
	var stats: Dictionary = StatSystem.effective_stats("Buffalo", ["does_not_exist"])
	var base: Dictionary = StatSystem.base_stats_for("Buffalo")
	for k in StatSystem.STATS:
		if abs(float(stats[k]) - float(base[k])) > EPSILON:
			return _fail("unknown id ignored", "stat %s drifted from base" % k)
	return _pass("unknown id ignored")

static func _case_apply_purchase_blocks_unknown() -> Dictionary:
	var r: Dictionary = StatSystem.apply_purchase("does_not_exist", 99, [])
	if bool(r.ok):
		return _fail("apply_purchase rejects unknown", "expected ok=false")
	if String(r.reason) != StatSystem.REASON_UNKNOWN:
		return _fail("apply_purchase rejects unknown", "reason got %s" % r.reason)
	return _pass("apply_purchase rejects unknown id")

static func _case_apply_purchase_blocks_already_owned() -> Dictionary:
	var r: Dictionary = StatSystem.apply_purchase("shared_warm_cloak", 99, ["shared_warm_cloak"])
	if bool(r.ok) or String(r.reason) != StatSystem.REASON_ALREADY_OWNED:
		return _fail("apply_purchase rejects already-owned", "got %s" % r)
	return _pass("apply_purchase rejects already-owned")

static func _case_apply_purchase_blocks_missing_prereq() -> Dictionary:
	# shared_spear requires shared_iron_axe.
	var r: Dictionary = StatSystem.apply_purchase("shared_spear", 99, [])
	if bool(r.ok) or String(r.reason) != StatSystem.REASON_NO_PREREQ:
		return _fail("apply_purchase rejects missing prereq", "got %s" % r)
	return _pass("apply_purchase rejects missing prereq")

static func _case_apply_purchase_blocks_insufficient() -> Dictionary:
	# shared_warm_cloak costs 1 ember. With 0 embers → REASON_INSUFFICIENT.
	var r: Dictionary = StatSystem.apply_purchase("shared_warm_cloak", 0, [])
	if bool(r.ok) or String(r.reason) != StatSystem.REASON_INSUFFICIENT:
		return _fail("apply_purchase rejects insufficient", "got %s" % r)
	return _pass("apply_purchase rejects insufficient")

static func _case_apply_purchase_succeeds() -> Dictionary:
	var r: Dictionary = StatSystem.apply_purchase("shared_warm_cloak", 5, [])
	if not bool(r.ok):
		return _fail("apply_purchase happy path", "got %s" % r)
	if int(r.embers) != 4:
		return _fail("apply_purchase happy path", "embers got %d want 4" % int(r.embers))
	if not (r.owned_upgrades as Array).has("shared_warm_cloak"):
		return _fail("apply_purchase happy path", "owned list missing entry")
	return _pass("apply_purchase happy path")

# ── Helpers ──────────────────────────────────────────────────────────

static func _pass(label: String) -> Dictionary:
	return {"ok": true, "line": "  PASS  " + label}

static func _fail(label: String, detail: String) -> Dictionary:
	return {"ok": false, "line": "  FAIL  %s — %s" % [label, detail]}
