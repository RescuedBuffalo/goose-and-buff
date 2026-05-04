class_name WaveDirector extends RefCounted
##
## Pure round / wave state machine. Mirrors the Roblox WaveDirector contract:
## tick(dt) drives all time progression; signals announce transitions.
##
## States cycle: PREP -> WAVE -> DEBRIEF -> PREP, until either the run
## completes (3 rounds cleared) or the core falls.

const Waves := preload("res://data/waves.gd")

signal round_started(round_index: int)
signal wave_started(round_index: int, composition: Dictionary)
signal enemy_due(enemy_type: String, slot_index: int)
signal wave_ended(round_index: int, victory: bool)
signal run_complete()
signal run_ended()
signal prep_timer_changed(seconds_left: float)

const PREP_DURATION := 30.0
const DEBRIEF_DURATION := 5.0

enum State { PREP, WAVE, DEBRIEF, COMPLETE, ENDED }

var state: int = State.PREP
var round_index: int = 1
var _timer: float = PREP_DURATION
var _wave_composition: Dictionary = {}
var _spawn_queue: Array = []
var _spawn_accum: float = 0.0
var _enemies_alive: int = 0
var _wave_victory_pending: bool = false

func reset() -> void:
	state = State.PREP
	round_index = 1
	_timer = PREP_DURATION
	_wave_composition = {}
	_spawn_queue = []
	_spawn_accum = 0.0
	_enemies_alive = 0
	_wave_victory_pending = false
	round_started.emit(round_index)
	prep_timer_changed.emit(_timer)

func tick(dt: float) -> void:
	match state:
		State.PREP:
			_timer = max(0.0, _timer - dt)
			prep_timer_changed.emit(_timer)
			if _timer <= 0.0:
				_advance_to_wave()
		State.WAVE:
			_advance_spawn_queue(dt)
			if _spawn_queue.is_empty() and _enemies_alive <= 0:
				_advance_to_debrief(true)
		State.DEBRIEF:
			_timer = max(0.0, _timer - dt)
			if _timer <= 0.0:
				_advance_to_next_round()

func ready_round() -> void:
	# Player presses Ready during prep — skip the rest of the timer.
	if state == State.PREP:
		_timer = 0.0
		_advance_to_wave()

func note_enemy_spawned() -> void:
	_enemies_alive += 1

func note_enemy_killed() -> void:
	_enemies_alive = max(0, _enemies_alive - 1)

func note_core_destroyed() -> void:
	# Adapter calls this when the core's HP hits 0.
	if state == State.WAVE or state == State.PREP:
		_advance_to_debrief(false)

func is_wave_phase() -> bool:
	return state == State.WAVE

func is_prep_phase() -> bool:
	return state == State.PREP

# ── internals ─────────────────────────────────────────────────────────

func _advance_to_wave() -> void:
	state = State.WAVE
	_wave_composition = Waves.for_round(round_index)
	_spawn_queue = _build_spawn_queue(_wave_composition)
	_spawn_accum = 0.0
	wave_started.emit(round_index, _wave_composition)

func _advance_to_debrief(victory: bool) -> void:
	state = State.DEBRIEF
	_wave_victory_pending = victory
	_timer = DEBRIEF_DURATION
	wave_ended.emit(round_index, victory)

func _advance_to_next_round() -> void:
	if not _wave_victory_pending:
		state = State.ENDED
		run_ended.emit()
		return
	round_index += 1
	if round_index > Waves.TOTAL_ROUNDS:
		state = State.COMPLETE
		run_complete.emit()
		return
	state = State.PREP
	_timer = PREP_DURATION
	round_started.emit(round_index)
	prep_timer_changed.emit(_timer)

func _build_spawn_queue(composition: Dictionary) -> Array:
	var queue: Array = []
	for entry in composition.enemies:
		for i in entry.count:
			queue.append({
				"type": entry.type,
				"interval": entry.spawn_interval,
				"slot": i,
			})
	return queue

func _advance_spawn_queue(dt: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_accum += dt
	# Subtract per spawn rather than zeroing so a long frame catches the
	# queue up — important during stutters / breakpoints / low FPS, where
	# zeroing would silently slow the wave below its configured rate.
	while not _spawn_queue.is_empty():
		var next: Dictionary = _spawn_queue[0]
		var interval: float = float(next.interval)
		if _spawn_accum < interval:
			break
		_spawn_accum -= interval
		_spawn_queue.pop_front()
		enemy_due.emit(next.type, next.slot)
