class_name Telemetry extends RefCounted
##
## Pure event logger. Each event is a plain dict
## { ts, run_id, kind, payload }. Logic emits via `log()`; an adapter
## (telemetry_io.gd) listens on `event_logged` and persists asynchronously.
##
## No scene-tree references, no I/O, no engine singletons beyond Time +
## RandomNumberGenerator (deterministic surfaces; safe in pure logic).
##
## Privacy: run_id is a per-run nonce. No machine identifier, no IP, no
## user account, no persistent device ID. Audit any new payload before
## merging — only run-scoped event data is allowed.

signal event_logged(event: Dictionary)

const KIND_RUN_START := "run_start"
const KIND_RUN_END := "run_end"
const KIND_WAVE_START := "wave_start"
const KIND_WAVE_END := "wave_end"
const KIND_HERO_DAMAGE_TAKEN := "hero_damage_taken"
const KIND_HERO_KILLED_ENEMY := "hero_killed_enemy"
const KIND_RESOURCE_GATHERED := "resource_gathered"
const KIND_BUILDING_PLACED := "building_placed"
const KIND_ABILITY_CAST := "ability_cast"

var run_id: String = ""

func reset() -> void:
	run_id = ""

func start_run(payload: Dictionary = {}) -> String:
	run_id = _generate_run_id()
	self.log(KIND_RUN_START, payload)
	return run_id

func end_run(payload: Dictionary = {}) -> void:
	if run_id.is_empty():
		return
	self.log(KIND_RUN_END, payload)

func log(kind: String, payload: Dictionary = {}) -> void:
	# Drop events emitted before a run is active. start_run() is the
	# only legal way to seed run_id; logging before that is a wiring bug.
	if run_id.is_empty() and kind != KIND_RUN_START:
		return
	var event := {
		"ts": Time.get_unix_time_from_system(),
		"run_id": run_id,
		"kind": kind,
		"payload": payload,
	}
	event_logged.emit(event)

# Run id = unix-second + 16-bit random suffix. Collision-resistant within
# a single second; intentionally NOT a UUID so it can't double as a
# device-stable identifier.
func _generate_run_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ts: int = int(Time.get_unix_time_from_system())
	return "%d-%04x" % [ts, rng.randi() & 0xFFFF]
