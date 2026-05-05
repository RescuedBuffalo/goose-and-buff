class_name SaveState extends RefCounted
##
## Pure data + serialization for the cross-run save file (BUF-142).
##
## State shape:
##   {
##     "version": int,                  # SCHEMA_VERSION at write time
##     "runs": Array[RunRecord],        # newest first, capped at MAX_RUNS
##     "unlocks": Dictionary,           # reserved (BUF-113 re-port + future)
##     "lodge_artifacts": Array,        # reserved for BUF-130
##     "current_variants": Dictionary,  # reserved for BUF-129 (hero_id → variant_id)
##   }
##
## RunRecord shape:
##   {
##     "ended_at": int,                 # unix epoch seconds
##     "outcome": String,               # "victory" or "defeat"
##     "hero_id": String,
##     "nights_survived": int,
##     "resources_gathered": int,
##     "enemies_felled": int,
##     "duration_seconds": float,
##   }
##
## Pure: no FileAccess, no scene tree, no autoloads. The save_io adapter
## owns the JSON file; this module owns the shape.

const SCHEMA_VERSION := 1
const MAX_RUNS := 10

const OUTCOME_VICTORY := "victory"
const OUTCOME_DEFEAT := "defeat"

# ── Construction ─────────────────────────────────────────────────────────

static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"runs": [],
		"unlocks": {},
		"lodge_artifacts": [],
		"current_variants": {},
	}

static func make_run_record(
	hero_id: String,
	outcome: String,
	nights_survived: int,
	resources_gathered: int,
	enemies_felled: int,
	duration_seconds: float,
	ended_at_epoch: int,
) -> Dictionary:
	return {
		"ended_at": ended_at_epoch,
		"outcome": outcome,
		"hero_id": hero_id,
		"nights_survived": nights_survived,
		"resources_gathered": resources_gathered,
		"enemies_felled": enemies_felled,
		"duration_seconds": duration_seconds,
	}

# ── Mutators (pure: return a new state, do not mutate the input) ────────

static func append_run(state: Dictionary, record: Dictionary) -> Dictionary:
	# Newest first so last_run() is O(1) and the lodge list reads
	# top-to-bottom in chronological reverse without an extra sort.
	var runs: Array = (state.get("runs", []) as Array).duplicate()
	runs.push_front(record)
	if runs.size() > MAX_RUNS:
		runs.resize(MAX_RUNS)
	var out := state.duplicate(true)
	out["runs"] = runs
	out["version"] = SCHEMA_VERSION
	return out

# ── Accessors ────────────────────────────────────────────────────────────

static func last_run(state: Dictionary) -> Dictionary:
	var runs: Array = state.get("runs", [])
	if runs.is_empty():
		return {}
	var first: Variant = runs[0]
	if typeof(first) != TYPE_DICTIONARY:
		return {}
	return first

static func runs(state: Dictionary) -> Array:
	return state.get("runs", [])

# ── Serialization ────────────────────────────────────────────────────────

static func to_json(state: Dictionary) -> String:
	return JSON.stringify(state, "\t")

static func from_json(text: String) -> Dictionary:
	# Empty file or unparseable JSON → fresh state. Callers should treat
	# this the same as "no save exists".
	if text.strip_edges().is_empty():
		return empty()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return empty()
	return coerce(parsed)

# ── Migration / defensive coercion ───────────────────────────────────────
#
# Saves written by older builds may be missing keys added later (variants,
# artifacts will append fields per the issue). Fill missing keys from
# defaults rather than throwing the file away. A version newer than this
# build can't be safely interpreted, so reset to fresh — better than
# crashing on a key we don't understand.

static func coerce(loaded: Dictionary) -> Dictionary:
	var v: int = int(loaded.get("version", 0))
	if v > SCHEMA_VERSION:
		push_warning("save_data.json is v%d but build expects v%d — using fresh save" % [v, SCHEMA_VERSION])
		return empty()
	var base := empty()
	for key in base.keys():
		if loaded.has(key):
			base[key] = loaded[key]
	# Type guards on the top-level fields we actually depend on. Anything
	# malformed gets replaced with defaults so a single corrupt key can't
	# brick the lodge.
	if typeof(base["runs"]) != TYPE_ARRAY:
		base["runs"] = []
	else:
		var clean_runs: Array = []
		for r in base["runs"]:
			if typeof(r) == TYPE_DICTIONARY:
				clean_runs.append(_coerce_run(r))
			if clean_runs.size() >= MAX_RUNS:
				break
		base["runs"] = clean_runs
	if typeof(base["unlocks"]) != TYPE_DICTIONARY:
		base["unlocks"] = {}
	if typeof(base["lodge_artifacts"]) != TYPE_ARRAY:
		base["lodge_artifacts"] = []
	if typeof(base["current_variants"]) != TYPE_DICTIONARY:
		base["current_variants"] = {}
	base["version"] = SCHEMA_VERSION
	return base

static func _coerce_run(r: Dictionary) -> Dictionary:
	# Fill any missing per-run fields with safe defaults. A run record
	# read back from disk through JSON.parse_string can have ints come
	# through as floats; cast back so consumers see the types they expect.
	return {
		"ended_at": int(r.get("ended_at", 0)),
		"outcome": String(r.get("outcome", OUTCOME_DEFEAT)),
		"hero_id": String(r.get("hero_id", "")),
		"nights_survived": int(r.get("nights_survived", 0)),
		"resources_gathered": int(r.get("resources_gathered", 0)),
		"enemies_felled": int(r.get("enemies_felled", 0)),
		"duration_seconds": float(r.get("duration_seconds", 0.0)),
	}
