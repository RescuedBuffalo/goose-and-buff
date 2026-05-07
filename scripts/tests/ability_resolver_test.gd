class_name AbilityResolverTest extends RefCounted
##
## Scratch wiring test for AbilityResolver (BUF-156 acceptance: each of
## the three signature abilities resolves to a real effect, not [], when
## the resolver is asked to dispatch them).
##
## Same shape as stat_system_test.gd — no test framework, just static
## closures that print PASS/FAIL. Bound to F12 alongside the other
## scratch tests so devs can run from the running game.
##
## Cases cover:
##   1. resolve("BuffaloCharge") → damage_in_capsule effect with the
##      Cards payload values. Locks in the Buffalo branch.
##   2. resolve("Dive") → damage_in_cone. Validates that card.dive exists
##      in cards.gd; without it the resolver crashed on dictionary access.
##   3. resolve("Snatch") → dash_and_strike with dash distance ≤ max_dash.
##      Same wiring guarantee as Dive plus the range-cap check.
##   4. resolve("Unknown") → []. Sanity for the default branch.

const AbilityResolver := preload("res://scripts/logic/ability_resolver.gd")
const Cards := preload("res://data/cards.gd")

static func run_all() -> Dictionary:
	var results: Array = []
	var passed: int = 0
	var failed: int = 0
	var cases: Array = [
		_case_buffalo_charge_resolves,
		_case_dive_resolves,
		_case_snatch_resolves_within_range,
		_case_unknown_returns_empty,
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
	print("── AbilityResolver wiring test ───────────────────────")
	for line in report.results:
		print(line)
	print("── %d passed, %d failed" % [int(report.passed), int(report.failed)])

# ── Cases ────────────────────────────────────────────────────────────

static func _case_buffalo_charge_resolves() -> Dictionary:
	var effects: Array = AbilityResolver.resolve("BuffaloCharge", Vector2.ZERO, Vector2(100, 0))
	if effects.size() != 1:
		return {"ok": false, "line": "FAIL: BuffaloCharge effect count = %d" % effects.size()}
	var e: Dictionary = effects[0]
	if String(e.get("kind", "")) != "damage_in_capsule":
		return {"ok": false, "line": "FAIL: BuffaloCharge kind = %s" % String(e.get("kind", ""))}
	var payload: Dictionary = Cards.get_card("card.charge").payload
	if abs(float(e.get("damage", 0.0)) - float(payload.damage)) > 0.001:
		return {"ok": false, "line": "FAIL: BuffaloCharge damage mismatched"}
	return {"ok": true, "line": "PASS: BuffaloCharge → damage_in_capsule"}

static func _case_dive_resolves() -> Dictionary:
	var effects: Array = AbilityResolver.resolve("Dive", Vector2.ZERO, Vector2(100, 0))
	if effects.size() != 1:
		return {"ok": false, "line": "FAIL: Dive effect count = %d (card.dive missing?)" % effects.size()}
	var e: Dictionary = effects[0]
	if String(e.get("kind", "")) != "damage_in_cone":
		return {"ok": false, "line": "FAIL: Dive kind = %s" % String(e.get("kind", ""))}
	# half_angle is stored in radians; the card payload stores degrees.
	var payload: Dictionary = Cards.get_card("card.dive").payload
	var expected_half_angle: float = deg_to_rad(float(payload.half_angle_deg))
	if abs(float(e.get("half_angle", 0.0)) - expected_half_angle) > 0.001:
		return {"ok": false, "line": "FAIL: Dive half_angle conversion off"}
	return {"ok": true, "line": "PASS: Dive → damage_in_cone"}

static func _case_snatch_resolves_within_range() -> Dictionary:
	# Target far beyond max_dash → resolver caps the dash. Validates both
	# that card.snatch resolves and that the range-cap behaviour holds.
	var payload: Dictionary = Cards.get_card("card.snatch").payload
	var max_dash: float = float(payload.max_dash)
	var effects: Array = AbilityResolver.resolve("Snatch", Vector2.ZERO, Vector2(max_dash * 4.0, 0))
	if effects.size() != 1:
		return {"ok": false, "line": "FAIL: Snatch effect count = %d (card.snatch missing?)" % effects.size()}
	var e: Dictionary = effects[0]
	if String(e.get("kind", "")) != "dash_and_strike":
		return {"ok": false, "line": "FAIL: Snatch kind = %s" % String(e.get("kind", ""))}
	var dash_to: Vector2 = e.get("to", Vector2.ZERO)
	if dash_to.length() > max_dash + 0.001:
		return {"ok": false, "line": "FAIL: Snatch dash exceeded max_dash"}
	return {"ok": true, "line": "PASS: Snatch → dash_and_strike (range-capped)"}

static func _case_unknown_returns_empty() -> Dictionary:
	var effects: Array = AbilityResolver.resolve("DefinitelyNotARealAbility", Vector2.ZERO, Vector2.ZERO)
	if effects.size() != 0:
		return {"ok": false, "line": "FAIL: unknown ability returned %d effects" % effects.size()}
	return {"ok": true, "line": "PASS: unknown ability → []"}
