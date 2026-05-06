extends Node
##
## File-I/O adapter for the save state (BUF-142).
##
## Holds the loaded SaveState dictionary in memory between scene changes
## (registered as the SaveIo autoload). Pure logic for the schema lives
## in scripts/logic/save_state.gd; this file just talks to FileAccess.
##
## JSON, not Resource: the file is human-readable so we can eyeball saves
## during dev, and the data set is small enough that perf isn't a concern.
## Switch to a binary Resource if save size ever becomes a problem (it
## won't — we cap at MAX_RUNS records).

const SaveStateClass := preload("res://scripts/logic/save_state.gd")
const StatSystemClass := preload("res://scripts/logic/stat_system.gd")
const ArtifactsData := preload("res://data/lodge_artifacts.gd")
const Upgrades := preload("res://data/upgrades.gd")
const HeroVariants := preload("res://data/hero_variants.gd")

const SAVE_PATH := "user://save_data.json"
const SAVE_PATH_TMP := "user://save_data.json.tmp"

# BUF-149: ember spends happen at the lodge between runs, so they don't
# fit inside a per-run telemetry file. We append them to a separate
# lodge events stream alongside the run files; offline analysis treats
# the lodge file like any other JSONL telemetry source.
const LODGE_EVENTS_DIR := "user://telemetry"
const LODGE_EVENTS_PATH := "user://telemetry/lodge_events.jsonl"

signal state_changed()
# BUF-149: emitted from purchase_upgrade so any active scene-tree consumer
# (telemetry IO, HUD pulse, etc.) can pick up the spend. The disk write
# inside _emit_lodge_event is independent of subscribers.
signal embers_spent(upgrade_id: String, amount: int)

var data: Dictionary = {}

func _ready() -> void:
	data = _load_or_fresh()

# ── Load / save ──────────────────────────────────────────────────────────

func _load_or_fresh() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return SaveStateClass.empty()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("save_data.json exists but could not be opened — using fresh save")
		return SaveStateClass.empty()
	var raw := f.get_as_text()
	f.close()
	return SaveStateClass.from_json(raw)

func save() -> void:
	# Atomic write: serialize to .tmp, then rename over the real file.
	# DirAccess.rename overwrites the target atomically on POSIX
	# (rename(2)) and Windows (MoveFileEx + REPLACE_EXISTING) — a crash
	# anywhere in this function leaves either the old or the new save
	# intact, never a half-written one.
	var f := FileAccess.open(SAVE_PATH_TMP, FileAccess.WRITE)
	if f == null:
		push_error("SaveIo: could not open %s for write" % SAVE_PATH_TMP)
		return
	f.store_string(SaveStateClass.to_json(data))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveIo: could not open user:// to finalize save")
		return
	var err := dir.rename("save_data.json.tmp", "save_data.json")
	if err != OK:
		push_error("SaveIo: rename save_data.json.tmp → save_data.json failed (err %d) — previous save preserved" % err)
		return
	state_changed.emit()

func reset() -> void:
	data = SaveStateClass.empty()
	save()

# ── Mutators ─────────────────────────────────────────────────────────────

func record_run(
	hero_id: String,
	outcome: String,
	nights_survived: int,
	resources_gathered: int,
	enemies_felled: int,
	duration_seconds: float,
	seed: int = 0,
) -> void:
	var now := int(Time.get_unix_time_from_system())
	var record := SaveStateClass.make_run_record(
		hero_id,
		outcome,
		nights_survived,
		resources_gathered,
		enemies_felled,
		duration_seconds,
		now,
		seed,
	)
	data = SaveStateClass.append_run(data, record)
	# Every completed run leaves a mark — victory or defeat (BUF-130). The
	# lodge accumulates regardless of outcome; the room remembers more than
	# the heroes do. Draw + accumulate happen in the same save call so a
	# crash between record_run and add_artifact can't leave the run logged
	# without its artifact (or vice versa).
	var artifact_id := _draw_artifact_id()
	if artifact_id != "":
		var artifact_record := SaveStateClass.make_artifact_record(artifact_id, outcome, now)
		data = SaveStateClass.append_artifact(data, artifact_record)
	save()

func _draw_artifact_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return ArtifactsData.draw(rng)

# ── M2: embers + upgrades (BUF-147) ──────────────────────────────────────

func add_embers(amount: int) -> int:
	# Mutates + persists. Returns the new balance.
	data = SaveStateClass.add_embers(data, amount)
	save()
	return SaveStateClass.embers(data)

func purchase_upgrade(upgrade_id: String) -> Dictionary:
	# Pure stat-system computes the new state; the adapter persists it.
	# Returns the same {ok, embers, owned_upgrades, reason} dict the
	# pure logic produces so callers can render rejection states.
	var before_embers: int = SaveStateClass.embers(data)
	var result: Dictionary = StatSystemClass.apply_purchase(
		upgrade_id,
		before_embers,
		SaveStateClass.owned_upgrades(data),
	)
	if result.ok:
		data = SaveStateClass.set_embers(data, int(result.embers))
		data = SaveStateClass.set_owned_upgrades(data, result.owned_upgrades)
		save()
		# Telemetry: ember_spent (BUF-149 acceptance). Recorded against the
		# lodge stream rather than a per-run id since spends happen between
		# runs. Payload mirrors ember_earned plus the upgrade id.
		var spent: int = before_embers - int(result.embers)
		var upgrade: Dictionary = Upgrades.by_id(upgrade_id)
		_emit_lodge_event("ember_spent", {
			"upgrade_id": upgrade_id,
			"amount": spent,
			"hero_scope": String(upgrade.get("hero", "")),
			"tier": int(upgrade.get("tier", 0)),
			"balance_after": int(result.embers),
		})
		embers_spent.emit(upgrade_id, spent)
	return result

func embers() -> int:
	return SaveStateClass.embers(data)

func owned_upgrades() -> Array:
	return SaveStateClass.owned_upgrades(data)

# ── M2: hero variants (BUF-129) ──────────────────────────────────────────

func assign_variant_for_run(hero_id: String) -> String:
	# Picks a fresh variant for the active hero and persists it. Called
	# from run_start when the player confirms a hero — guarantees the new
	# pick differs from the previous one when the pool has more than one
	# entry, so the rotation requirement in BUF-129 lands deterministically
	# instead of "different ~75% of the time". Empty pool → "" so the data
	# layer can ship before assets do.
	var pool: Array = HeroVariants.for_hero(hero_id)
	if pool.is_empty():
		return ""
	var current: String = current_variant(hero_id)
	# Exclude the current variant if we have alternatives; otherwise the
	# single-entry pool falls back to itself (no rotation possible).
	var candidates: Array = pool
	if pool.size() > 1 and not current.is_empty():
		candidates = []
		for v in pool:
			if String(v.get("id", "")) != current:
				candidates.append(v)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var picked_id: String = String(pick.get("id", ""))
	data = SaveStateClass.set_variant(data, hero_id, picked_id)
	save()
	return picked_id

func ensure_variant(hero_id: String) -> String:
	# Returns the hero's current variant, rolling one only if none is set.
	# Used by run_start.gd to populate the hero-select cards on first
	# entry, and by main.gd as a fallback when main.tscn is launched
	# directly (no preceding run_start.tscn). Stable for the run.
	var current: String = current_variant(hero_id)
	if not current.is_empty():
		return current
	return assign_variant_for_run(hero_id)

func current_variant(hero_id: String) -> String:
	return SaveStateClass.variant_for(data, hero_id)

# ── M2: debug helpers (BUF-147 acceptance) ───────────────────────────────
##
## QA testing affordances. Bound to F5 / F6 / F12 in main.gd so a play
## session can grant embers, fully unlock the tree, or rerun the stat-
## composition test without leaving the running game. Saves are not
## sandboxed — using these mutates the player's actual save file. Fine
## for the three-friends prototype, gate by an "engine.is_editor_hint()"
## or build flag if the project ever ships externally.

func debug_grant_embers(amount: int) -> int:
	# Adds embers without going through award_for_run. Mirrors the
	# normal add path so listeners (lodge embers panel) repaint via the
	# state_changed signal that save() emits.
	if amount <= 0:
		return embers()
	data = SaveStateClass.add_embers(data, amount)
	save()
	return embers()

func debug_grant_upgrade(upgrade_id: String) -> bool:
	# Adds the upgrade id to owned without checking cost or prereqs.
	# Returns false if the id isn't in data/upgrades.gd. Useful for
	# probing a specific stat path mid-run; F6 grants the whole pool.
	var u: Dictionary = Upgrades.by_id(upgrade_id)
	if u.is_empty():
		return false
	var owned: Array = (SaveStateClass.owned_upgrades(data) as Array).duplicate()
	if not owned.has(upgrade_id):
		owned.append(upgrade_id)
		data = SaveStateClass.set_owned_upgrades(data, owned)
		save()
	return true

func debug_revoke_upgrade(upgrade_id: String) -> bool:
	var owned: Array = (SaveStateClass.owned_upgrades(data) as Array).duplicate()
	var idx: int = owned.find(upgrade_id)
	if idx < 0:
		return false
	owned.remove_at(idx)
	data = SaveStateClass.set_owned_upgrades(data, owned)
	save()
	return true

func debug_grant_all_upgrades() -> int:
	# Grants every authored upgrade. Returns the new owned count. Lets QA
	# verify max-stack stat composition without grinding through embers.
	var owned: Array = (SaveStateClass.owned_upgrades(data) as Array).duplicate()
	for u in Upgrades.ALL:
		var id: String = String(u.id)
		if not owned.has(id):
			owned.append(id)
	data = SaveStateClass.set_owned_upgrades(data, owned)
	save()
	return owned.size()

func debug_clear_progression() -> void:
	# Wipes embers + owned upgrades + current_variants. Run history /
	# artifacts are preserved so the QA flow doesn't lose context. For
	# a full reset use reset() (defined above).
	data = SaveStateClass.set_embers(data, 0)
	data = SaveStateClass.set_owned_upgrades(data, [])
	data = SaveStateClass.set_variants(data, {})
	save()

# ── Telemetry: lodge events (BUF-149) ────────────────────────────────────
##
## ember_spent fires from the lodge — outside of any active run. We don't
## have a Telemetry instance to log against (those live inside main.gd's
## logic modules), so SaveIo writes a separate JSONL file alongside the
## per-run telemetry. The event shape mirrors Telemetry.log() so any
## offline analysis tool can drain the lodge file the same way.

func _emit_lodge_event(kind: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(LODGE_EVENTS_DIR)
	var event := {
		"ts": Time.get_unix_time_from_system(),
		"kind": kind,
		"payload": payload,
	}
	var f: FileAccess
	if FileAccess.file_exists(LODGE_EVENTS_PATH):
		f = FileAccess.open(LODGE_EVENTS_PATH, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(LODGE_EVENTS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveIo: unable to open %s for lodge telemetry" % LODGE_EVENTS_PATH)
		return
	f.store_line(JSON.stringify(event))
	f.close()

# ── Accessors ────────────────────────────────────────────────────────────

func last_run() -> Dictionary:
	return SaveStateClass.last_run(data)

func runs() -> Array:
	return SaveStateClass.runs(data)

func artifacts() -> Array:
	return SaveStateClass.artifacts(data)
