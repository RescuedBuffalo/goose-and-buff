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
const ArtifactsData := preload("res://data/lodge_artifacts.gd")

const SAVE_PATH := "user://save_data.json"
const SAVE_PATH_TMP := "user://save_data.json.tmp"

signal state_changed()

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

# ── Accessors ────────────────────────────────────────────────────────────

func last_run() -> Dictionary:
	return SaveStateClass.last_run(data)

func runs() -> Array:
	return SaveStateClass.runs(data)

func artifacts() -> Array:
	return SaveStateClass.artifacts(data)
