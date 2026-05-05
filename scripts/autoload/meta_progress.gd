extends Node
##
## Meta-progression: tokens earned across runs, cards unlocked per hero, and
## per-hero deck swaps that overlay the starter deck on the next run.
##
## Single source of truth for between-run state. Persisted to user:// so it
## survives quitting; the in-run modules (CardSystem, Economy) stay pure
## and read swaps once at run start via build_deck_for(hero_id).
##
## Currency model (v0): a flat grant per outcome — victory pays more than
## defeat, but defeat still pays something so a losing streak still inches
## the player forward. Tune by editing the TOKENS_* constants.

const Cards := preload("res://data/cards.gd")

const SAVE_PATH := "user://meta_progress.save"
const SAVE_VERSION := 1
const TOKENS_PER_VICTORY := 5
const TOKENS_PER_DEFEAT := 1
const UNLOCK_COST := 3

signal tokens_changed(new_balance: int)
signal hero_changed(hero_id: String)

var tokens: int = 0
# hero_id -> Array[String] of card ids the player has unlocked.
var unlocked: Dictionary = {"Buffalo": [], "Goose": [], "Fox": []}
# hero_id -> Dictionary[String, String]; starter_card_id -> unlocked_card_id.
# An entry means "in this hero's deck, replace one copy of the starter card
# with the unlocked card". Cleared automatically if the unlocked card is
# re-locked (shouldn't happen in v0) or if the player toggles it back out.
var swaps: Dictionary = {"Buffalo": {}, "Goose": {}, "Fox": {}}

func _ready() -> void:
	_load()

# ── Token economy ─────────────────────────────────────────────────────────

func grant_for_outcome(victory: bool) -> int:
	var amount := TOKENS_PER_VICTORY if victory else TOKENS_PER_DEFEAT
	tokens += amount
	tokens_changed.emit(tokens)
	_save()
	return amount

func can_afford_unlock() -> bool:
	return tokens >= UNLOCK_COST

# ── Card unlocks ──────────────────────────────────────────────────────────

func unlock_card(hero_id: String, card_id: String) -> bool:
	if not _is_in_pool(hero_id, card_id):
		return false
	if is_unlocked(hero_id, card_id):
		return false
	if not can_afford_unlock():
		return false
	tokens -= UNLOCK_COST
	if not unlocked.has(hero_id):
		unlocked[hero_id] = []
	unlocked[hero_id].append(card_id)
	tokens_changed.emit(tokens)
	hero_changed.emit(hero_id)
	_save()
	return true

func is_unlocked(hero_id: String, card_id: String) -> bool:
	var hero_unlocks: Array = unlocked.get(hero_id, [])
	return hero_unlocks.has(card_id)

# ── Deck swaps ────────────────────────────────────────────────────────────

func is_in_deck(hero_id: String, card_id: String) -> bool:
	# True if `card_id` (an unlocked card) is currently swapped into this
	# hero's deck. We scan values rather than store a reverse index — the
	# swap dict is at most ~7 entries.
	var hero_swaps: Dictionary = swaps.get(hero_id, {})
	for v in hero_swaps.values():
		if v == card_id:
			return true
	return false

func toggle_in_deck(hero_id: String, card_id: String) -> void:
	# Adds or removes `card_id` from the hero's deck. The unlock card's
	# `replaces` field decides which starter slot it claims; clicking once
	# adds, clicking again removes. Adding overwrites any other unlock card
	# that previously occupied the same slot — only one swap per slot.
	if not is_unlocked(hero_id, card_id):
		return
	if not swaps.has(hero_id):
		swaps[hero_id] = {}
	var hero_swaps: Dictionary = swaps[hero_id]
	# Already in deck? Toggle it out.
	for starter_id in hero_swaps.keys():
		if hero_swaps[starter_id] == card_id:
			hero_swaps.erase(starter_id)
			hero_changed.emit(hero_id)
			_save()
			return
	# Not in deck. Add it, displacing any other unlock on the same slot.
	var card: Dictionary = Cards.get_card(card_id)
	var slot: String = card.get("replaces", "")
	if slot == "":
		return
	hero_swaps[slot] = card_id
	hero_changed.emit(hero_id)
	_save()

# Returns the per-hero deck the next run should use, with swaps applied.
# Pure passthrough to Cards.apply_swaps so any caller (UI preview, run start)
# sees the same deck composition.
func build_deck_for(hero_id: String) -> Array:
	var base := Cards.build_starter_deck(hero_id)
	return Cards.apply_swaps(base, swaps.get(hero_id, {}))

# ── Persistence ───────────────────────────────────────────────────────────

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var payload := {
		"version": SAVE_VERSION,
		"tokens": tokens,
		"unlocked": unlocked,
		"swaps": swaps,
	}
	f.store_string(JSON.stringify(payload))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return
	tokens = int(data.get("tokens", 0))
	# JSON stores arrays/dicts as Variant — coerce to String values so the
	# downstream `find()` and equality checks behave like the in-memory shape.
	var raw_unlocked: Dictionary = data.get("unlocked", {})
	for hid in unlocked.keys():
		var arr: Array = []
		for v in raw_unlocked.get(hid, []):
			arr.append(String(v))
		unlocked[hid] = arr
	var raw_swaps: Dictionary = data.get("swaps", {})
	for hid in swaps.keys():
		var d: Dictionary = {}
		var src: Dictionary = raw_swaps.get(hid, {})
		for k in src.keys():
			d[String(k)] = String(src[k])
		swaps[hid] = d

# ── Internals ─────────────────────────────────────────────────────────────

func _is_in_pool(hero_id: String, card_id: String) -> bool:
	var pool: Array = Cards.UNLOCK_POOLS.get(hero_id, [])
	return pool.has(card_id)
