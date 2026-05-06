class_name WaveDirector extends RefCounted
##
## Pure wave spawn-queue driver. The wave-defense build owned phase
## transitions itself (PREP → WAVE → DEBRIEF on internal timers); the
## survival rebuild moves phase ownership into DayNightCycle and leaves
## WaveDirector as a stateless-ish queue that turns on at dusk→night and
## off at night→dawn.
##
## Public surface used by the survival adapters:
##   reset()                       — return to IDLE, clear counters
##   start_wave(round_index)       — externally driven entry into WAVE
##   end_wave()                    — externally driven exit from WAVE
##   tick(dt)                      — drains the spawn queue while in WAVE
##   note_enemy_spawned/killed()   — adapter feedback for live counts
##   is_wave_active()              — readback for guards
##
## Old PREP/DEBRIEF logic + auto round-advance was removed during the
## conversion (BUF-136). The composition data and spawn queue mechanics
## are unchanged — only the driving harness is.

const Waves := preload("res://data/waves.gd")

signal wave_started(round_index: int, composition: Dictionary)
signal enemy_due(enemy_type: String, slot_index: int)
signal wave_ended(round_index: int)

enum State { IDLE, WAVE }

var state: int = State.IDLE
var round_index: int = 0
var _wave_composition: Dictionary = {}
var _spawn_queue: Array = []
var _spawn_accum: float = 0.0
var _enemies_alive: int = 0
# Per-run RNG seeded from the run seed (BUF-151 determinism). Picking
# a wave archetype on round 2 used to call randi() against the engine
# global RNG — fine in solo, but in multiplayer different peers would
# drift to different archetypes. Seeding with the run seed makes the
# pick reproducible across machines.
var _rng: RandomNumberGenerator = null

func reset() -> void:
	state = State.IDLE
	round_index = 0
	_wave_composition = {}
	_spawn_queue = []
	_spawn_accum = 0.0
	_enemies_alive = 0

func set_seed(seed: int) -> void:
	# Called by main.gd after the run seed is known. Caller passes
	# `run_seed` (BUF-151); wave_director uses it for archetype rolls.
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed

func start_wave(idx: int) -> void:
	# Idempotent — if a wave is already running, end it first so the
	# new one starts from a clean queue. Should not normally happen
	# (DayNightCycle gates this), but the guard keeps state honest.
	if state == State.WAVE:
		_clear_queue()
	state = State.WAVE
	round_index = idx
	_wave_composition = Waves.for_round(idx, _rng)
	_spawn_queue = _build_spawn_queue(_wave_composition)
	_spawn_accum = 0.0
	wave_started.emit(round_index, _wave_composition)

func end_wave() -> void:
	if state != State.WAVE:
		return
	_clear_queue()
	state = State.IDLE
	wave_ended.emit(round_index)

func tick(dt: float) -> void:
	if state != State.WAVE:
		return
	_advance_spawn_queue(dt)

func note_enemy_spawned() -> void:
	_enemies_alive += 1

func note_enemy_killed() -> void:
	_enemies_alive = max(0, _enemies_alive - 1)

func is_wave_active() -> bool:
	return state == State.WAVE

func enemies_alive() -> int:
	return _enemies_alive

# ── internals ─────────────────────────────────────────────────────────

func _clear_queue() -> void:
	_spawn_queue = []
	_spawn_accum = 0.0
	_enemies_alive = 0

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
	while not _spawn_queue.is_empty():
		var next: Dictionary = _spawn_queue[0]
		var interval: float = float(next.interval)
		if _spawn_accum < interval:
			break
		_spawn_accum -= interval
		_spawn_queue.pop_front()
		enemy_due.emit(next.type, next.slot)
