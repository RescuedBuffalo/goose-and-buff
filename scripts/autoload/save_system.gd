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

const Cards := preload("res://data/cards.gd")

signal save_reset()
# Emitted when meta-progression state visible to the Lodge changes — tokens
# spent, a new card unlocked, a swap toggled. UI listens to redraw.
signal meta_changed()

const SAVE_PATH := "user://save.json"
const SAVE_PATH_TMP := "user://save.json.tmp"
const SCHEMA_VERSION := 1

# Token economy (BUF-113). Currency grant per outcome and the flat cost to
# unlock any single card. Tune by editing these constants.
const TOKENS_PER_VICTORY := 5
const TOKENS_PER_DEFEAT := 1
const UNLOCK_COST := 3

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
		"swaps": _default_swaps(),
		"run_count": 0,
		"wins": 0,
		"losses": 0,
		"hero_progression": _default_hero_progression(),
		"last_hero_id": "",
	}

func _default_swaps() -> Dictionary:
	# Per-hero map: starter_card_id -> unlocked_card_id. Each entry says
	# "in this hero's deck, swap one copy of the starter for the unlock".
	var out := {}
	for hid in HERO_IDS:
		out[hid] = {}
	return out

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
	# `swaps` was added in BUF-113. Older saves won't have it; defensively
	# repair malformed shapes the same way as hero_progression.
	if typeof(base.swaps) != TYPE_DICTIONARY:
		base.swaps = _default_swaps()
	for hid in HERO_IDS:
		var sblock: Variant = base.swaps.get(hid, null)
		if typeof(sblock) != TYPE_DICTIONARY:
			base.swaps[hid] = {}
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

# ── Meta-progression (BUF-113) ──────────────────────────────────────────────
# Currency, per-hero unlock pools, and deck swaps. Layered on top of the
# existing flat `unlocked_cards` array (a card id is in the unlocked pool of
# whichever hero owns the corresponding `Cards.UNLOCK_POOLS` entry).

func grant_for_outcome(victory: bool) -> int:
	# Grants the per-outcome token amount and returns it so the end screen
	# can surface "+N tokens earned" without re-deriving the constant.
	var amount := TOKENS_PER_VICTORY if victory else TOKENS_PER_DEFEAT
	add_meta_currency(amount)
	meta_changed.emit()
	return amount

func can_afford_unlock() -> bool:
	return get_meta_currency() >= UNLOCK_COST

func purchase_unlock(hero_id: String, card_id: String) -> bool:
	# Spends UNLOCK_COST tokens to add `card_id` to the unlocked pool. Fails
	# silently (returns false) on insufficient funds, an already-unlocked
	# card, or an id outside this hero's pool — UI uses the boolean to
	# decide whether to show success feedback.
	if not _is_in_pool(hero_id, card_id):
		return false
	if is_card_unlocked(card_id):
		return false
	if not can_afford_unlock():
		return false
	data.meta_currency = int(data.get("meta_currency", 0)) - UNLOCK_COST
	var unlocked: Array = data.get("unlocked_cards", [])
	unlocked.append(card_id)
	data.unlocked_cards = unlocked
	save()
	meta_changed.emit()
	return true

func unlocked_pool_for(hero_id: String) -> Array:
	# Subset of `unlocked_cards` that belongs to this hero's UNLOCK_POOL.
	# UI iterates this when listing what the player can swap into the deck.
	var out: Array = []
	var pool: Array = Cards.UNLOCK_POOLS.get(hero_id, [])
	for cid in data.get("unlocked_cards", []):
		if pool.has(String(cid)):
			out.append(String(cid))
	return out

func is_card_in_deck(hero_id: String, card_id: String) -> bool:
	var hero_swaps: Dictionary = data.swaps.get(hero_id, {})
	for v in hero_swaps.values():
		if v == card_id:
			return true
	return false

func toggle_card_in_deck(hero_id: String, card_id: String) -> void:
	# Adds or removes `card_id` from this hero's deck swap. The card's
	# `replaces` field decides which starter slot it occupies; clicking
	# once adds, clicking again removes. Adding overwrites any other
	# unlock card already on the same slot — one swap per slot.
	if not is_card_unlocked(card_id):
		return
	if not data.swaps.has(hero_id):
		data.swaps[hero_id] = {}
	var hero_swaps: Dictionary = data.swaps[hero_id]
	for starter_id in hero_swaps.keys():
		if hero_swaps[starter_id] == card_id:
			hero_swaps.erase(starter_id)
			save()
			meta_changed.emit()
			return
	var card: Dictionary = Cards.get_card(card_id)
	var slot: String = String(card.get("replaces", ""))
	if slot == "":
		return
	hero_swaps[slot] = card_id
	save()
	meta_changed.emit()

func build_deck_for(hero_id: String) -> Array:
	# Starter deck with this hero's swaps applied — single source of truth
	# for the deck a run starts with. Pure passthrough so the UI's preview
	# and the run start see the exact same composition.
	var base := Cards.build_starter_deck(hero_id)
	return Cards.apply_swaps(base, data.swaps.get(hero_id, {}))

func _is_in_pool(hero_id: String, card_id: String) -> bool:
	var pool: Array = Cards.UNLOCK_POOLS.get(hero_id, [])
	return pool.has(card_id)
