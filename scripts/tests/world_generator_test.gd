class_name WorldGeneratorTest extends RefCounted
##
## Scratch determinism test for WorldGenerator (BUF-145 acceptance:
## "Same seed reproduces identical world").
##
## Same shape as stat_system_test.gd — no test framework, just static
## closures that print PASS/FAIL. Bound to F12 alongside the other
## scratch tests so devs can run from the running game.
##
## Cases cover:
##   1. Same (seed, day, hero) → byte-equal WorldDef (tiles + resources +
##      chunks). The seed-determinism guarantee the ticket asks for.
##   2. Different seeds on the same day produce different chunk layouts
##      (sanity — otherwise determinism is just "always the same world").
##   3. seed_to_string ↔ string_to_seed round-trip across sample seeds,
##      including the share-to-chat → paste-back path that the run-start
##      Copy button hands the player.
##   4. climate_weights_for_day matches the BUF-146 spec: day 1 weights
##      temperate-heavy, day 3 weights frozen-heavy. Locks the seasonal
##      shift so a future tweak can't quietly break the ticket's accept.

const WorldGenerator := preload("res://scripts/logic/world_generator.gd")
const Chunks := preload("res://data/chunks.gd")

static func run_all() -> Dictionary:
	var results: Array = []
	var passed: int = 0
	var failed: int = 0
	var cases: Array = [
		_case_same_seed_reproduces_world,
		_case_different_seeds_diverge,
		_case_seed_string_round_trip,
		_case_climate_weights_shift_with_day,
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
	print("── WorldGenerator determinism test ───────────────────")
	for line in report.results:
		print(line)
	print("── %d passed, %d failed" % [int(report.passed), int(report.failed)])

# ── Cases ────────────────────────────────────────────────────────────

static func _case_same_seed_reproduces_world() -> Dictionary:
	# Two generates with the same (seed, day, hero) must produce the
	# same chunk layout, the same tile grid, and the same resources.
	# We compare via JSON.stringify so Vector2i values inside dicts get
	# normalized consistently — `==` on dicts with Vector2i nested inside
	# arrays of dicts has surprised us before in Godot.
	var a: Dictionary = WorldGenerator.generate(0xA1B2C3D4, 2, "Buffalo")
	var b: Dictionary = WorldGenerator.generate(0xA1B2C3D4, 2, "Buffalo")
	if _world_signature(a) != _world_signature(b):
		return _fail("same seed reproduces world", "signatures diverged for seed 0xA1B2C3D4")
	# Sanity: stamp counts non-zero so we're not comparing two empty
	# dicts. Twenty-five chunks in a 5x5 grid, lodge tile sits in the
	# middle, resources_count > 0 because at least one infill template
	# always lands.
	if int(a.get("stats", {}).get("chunk_count", 0)) != 25:
		return _fail("same seed reproduces world", "chunk_count != 25 (got %d)" % int(a.get("stats", {}).get("chunk_count", 0)))
	return _pass("same seed reproduces world")

static func _case_different_seeds_diverge() -> Dictionary:
	# Cherry-picked seeds that we've eyeballed to produce visibly different
	# chunk layouts — the determinism test is only meaningful if the seed
	# actually drives variety. Two layouts that ALWAYS match across seeds
	# would mean the rng is wired to a constant somewhere.
	var a: Dictionary = WorldGenerator.generate(1, 2, "Buffalo")
	var b: Dictionary = WorldGenerator.generate(2, 2, "Buffalo")
	if _world_signature(a) == _world_signature(b):
		return _fail("different seeds diverge", "seeds 1 and 2 produced identical worlds")
	return _pass("different seeds diverge")

static func _case_seed_string_round_trip() -> Dictionary:
	# string_to_seed(seed_to_string(s)) must round-trip for every seed
	# the run-start Copy button is going to hand a player. Hex sampling
	# covers the 32-bit space without enumerating it.
	var samples: Array = [1, 0xFF, 0xDEADBEEF, 0x12345678, 0xA1B2C3D4]
	for s in samples:
		var encoded: String = WorldGenerator.seed_to_string(int(s))
		var decoded: int = WorldGenerator.string_to_seed(encoded)
		if decoded != int(s):
			return _fail("seed string round-trip", "%s -> %s -> %s" % [str(s), encoded, str(decoded)])
	# Empty / unparseable inputs return 0 (the "use random" sentinel).
	if WorldGenerator.string_to_seed("") != 0:
		return _fail("seed string round-trip", "empty string did not return 0")
	if WorldGenerator.string_to_seed("not-a-seed") != 0:
		return _fail("seed string round-trip", "garbage string did not return 0")
	return _pass("seed string round-trip")

static func _case_climate_weights_shift_with_day() -> Dictionary:
	# Day 1 leans temperate; day 3 leans frozen. The exact percentages
	# are locked by the BUF-146 ticket and live in data/chunks.gd —
	# this test pins them so a refactor can't quietly drift the seasonal
	# shift the player feels across nights.
	var d1: Dictionary = Chunks.climate_weights_for_day(1)
	if int(d1.get("temperate", 0)) != 70 or int(d1.get("frosted", 0)) != 25 or int(d1.get("frozen", 0)) != 5:
		return _fail("climate weights shift with day", "day 1 got %s want {temperate:70, frosted:25, frozen:5}" % str(d1))
	var d2: Dictionary = Chunks.climate_weights_for_day(2)
	if int(d2.get("temperate", 0)) != 30 or int(d2.get("frosted", 0)) != 50 or int(d2.get("frozen", 0)) != 20:
		return _fail("climate weights shift with day", "day 2 got %s want {temperate:30, frosted:50, frozen:20}" % str(d2))
	var d3: Dictionary = Chunks.climate_weights_for_day(3)
	if int(d3.get("temperate", 0)) != 10 or int(d3.get("frosted", 0)) != 40 or int(d3.get("frozen", 0)) != 50:
		return _fail("climate weights shift with day", "day 3 got %s want {temperate:10, frosted:40, frozen:50}" % str(d3))
	return _pass("climate weights shift with day")

# ── Helpers ──────────────────────────────────────────────────────────

static func _world_signature(world: Dictionary) -> String:
	# Hand-flattens Vector2i values so JSON.stringify can serialize the
	# whole structure without depending on undocumented Godot JSON
	# coercion behaviour. The string is opaque — only used for equality
	# comparison between two same-seed generations.
	var sig: Array = [
		world.get("seed", 0),
		world.get("day_index", 0),
		String(world.get("hero_id", "")),
		_chunks_to_plain(world.get("chunks", [])),
		world.get("tiles", []),
		_resources_to_plain(world.get("resources", [])),
	]
	return JSON.stringify(sig)

static func _chunks_to_plain(chunks: Array) -> Array:
	var out: Array = []
	for c in chunks:
		var pos: Vector2i = c.chunk_pos
		out.append([pos.x, pos.y, String(c.template_id), String(c.climate), String(c.get("biome", c.climate))])
	return out

static func _resources_to_plain(resources: Array) -> Array:
	var out: Array = []
	for r in resources:
		var tile: Vector2i = r.tile
		out.append([tile.x, tile.y, String(r.kind)])
	return out

static func _pass(label: String) -> Dictionary:
	return {"ok": true, "line": "  PASS  " + label}

static func _fail(label: String, detail: String) -> Dictionary:
	return {"ok": false, "line": "  FAIL  %s — %s" % [label, detail]}
