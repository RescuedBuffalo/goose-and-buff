extends Node
##
## Persistent meta-progression — survives an app close.
##
## Holds a single dictionary of cross-run state (meta currency, unlocked
## cards, run counters, per-hero progression) and persists it to
## `user://save.json`. Schema is versioned so future shape changes can
## migrate forward without trashing existing saves.
##
## Mutators (record_run_end / unlock_card / add_meta_currency / note_lodge_visit)
## save automatically; callers don't manage the file. Load happens on
## autoload _ready(), before main.gd runs.

signal save_reset()

const SAVE_PATH := "user://save.json"
const SAVE_PATH_TMP := "user://save.json.tmp"
const SCHEMA_VERSION := 1

# Mirrors data/heroes.gd ORDER. Duplicated here so SaveSystem stays free
# of a Heroes import (autoloads ready before regular scripts; pulling
# Heroes during _ready works but adds an unnecessary coupling).
const HERO_IDS := ["Goose", "Buffalo", "Fox"]

var data: Dictionary = {}

func _ready() -> void:
	data = _load_or_create()

# ── Persistence ─────────────────────────────────────────────────────────────

func _load_or_create() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _fresh()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("save.json exists but could not be opened — using fresh save")
		return _fresh()
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("save.json is not a JSON object — using fresh save")
		return _fresh()
	return _coerce(parsed)

func save() -> void:
	# Atomic write: serialize to .tmp, then rename over save.json. Godot's
	# DirAccess.rename overwrites the target atomically on both POSIX
	# (rename(2)) and Windows (MoveFileEx + MOVEFILE_REPLACE_EXISTING), so a
	# crash anywhere in this function leaves either the old or the new save
	# intact — never a partial file or a missing one.
	var f := FileAccess.open(SAVE_PATH_TMP, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: could not open %s for write" % SAVE_PATH_TMP)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveSystem: could not open user:// to finalize save")
		return
	var err := dir.rename("save.json.tmp", "save.json")
	if err != OK:
		push_error("SaveSystem: rename save.json.tmp → save.json failed (err %d) — previous save preserved" % err)

func reset() -> void:
	data = _fresh()
	save()
	save_reset.emit()

# ── Schema ──────────────────────────────────────────────────────────────────

func _fresh() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"meta_currency": 0,
		"unlocked_cards": [],
		"run_count": 0,
		"wins": 0,
		"losses": 0,
		"hero_progression": _default_hero_progression(),
		"last_hero_id": "",
	}

func _default_hero_progression() -> Dictionary:
	var out := {}
	for hid in HERO_IDS:
		out[hid] = _default_hero_block()
	return out

func _default_hero_block() -> Dictionary:
	return {"runs": 0, "wins": 0, "best_round": 0}

# Defensive merge: missing keys in the loaded file inherit defaults so a
# save written by an older build picks up new fields without losing what
# the player already had. Versions newer than the running build can't be
# safely interpreted; fall back to fresh rather than guessing.
func _coerce(loaded: Dictionary) -> Dictionary:
	var v: int = int(loaded.get("version", 0))
	if v > SCHEMA_VERSION:
		push_warning("save.json is v%d but build expects v%d — using fresh save" % [v, SCHEMA_VERSION])
		return _fresh()
	var base := _fresh()
	for key in base.keys():
		if loaded.has(key):
			base[key] = loaded[key]
	if typeof(base.hero_progression) != TYPE_DICTIONARY:
		base.hero_progression = _default_hero_progression()
	# Each hero block must itself be a dict — guard against a corrupted save
	# like {"Goose": 1} that would otherwise crash record_run_end on the
	# next run. Replace any malformed block with defaults rather than
	# refusing to load the whole save.
	for hid in HERO_IDS:
		var block: Variant = base.hero_progression.get(hid, null)
		if typeof(block) != TYPE_DICTIONARY:
			base.hero_progression[hid] = _default_hero_block()
	base.version = SCHEMA_VERSION
	return base

# ── Mutators ────────────────────────────────────────────────────────────────

func record_run_end(hero_id: String, victory: bool, final_round: int) -> void:
	data.run_count = int(data.get("run_count", 0)) + 1
	if victory:
		data.wins = int(data.get("wins", 0)) + 1
	else:
		data.losses = int(data.get("losses", 0)) + 1
	data.last_hero_id = hero_id
	var block: Dictionary = data.hero_progression.get(hero_id, _default_hero_block())
	block.runs = int(block.get("runs", 0)) + 1
	if victory:
		block.wins = int(block.get("wins", 0)) + 1
	if final_round > int(block.get("best_round", 0)):
		block.best_round = final_round
	data.hero_progression[hero_id] = block
	save()

func unlock_card(card_id: String) -> void:
	var unlocked: Array = data.get("unlocked_cards", [])
	if card_id in unlocked:
		return
	unlocked.append(card_id)
	data.unlocked_cards = unlocked
	save()

func is_card_unlocked(card_id: String) -> bool:
	return card_id in data.get("unlocked_cards", [])

func add_meta_currency(amount: int) -> void:
	data.meta_currency = int(data.get("meta_currency", 0)) + amount
	save()

func get_meta_currency() -> int:
	return int(data.get("meta_currency", 0))

func get_run_count() -> int:
	return int(data.get("run_count", 0))

func get_last_hero_id() -> String:
	return String(data.get("last_hero_id", ""))

func note_lodge_visit(hero_id: String = "") -> void:
	# Persist on every return to the lodge (currently hero select). Records
	# the most recent hero so a future "continue" affordance can preselect.
	if hero_id != "":
		data.last_hero_id = hero_id
	save()
