class_name DayNightCycle extends RefCounted
##
## Pure phase state machine. The survival rebuild's heartbeat: tick(dt)
## advances day → dusk → night → dawn → day, emitting transitions for
## the lighting + wave-gate adapters to react to.
##
## Phases progress automatically. There is no "ready" button — the day
## just ends when its timer runs out, and the night with it. The cycle
## owns its own day index; victory fires on the dawn AFTER MAX_NIGHTS.
##
## Defeat is NOT modeled here — lodge HP and hero HP are separate
## concerns. main.gd watches both and ends the run independently.

const DayNight := preload("res://data/day_night.gd")

enum Phase { DAY, DUSK, NIGHT, DAWN }

signal phase_changed(phase: int, day_index: int)
signal phase_timer_tick(seconds_left: float, phase: int)
signal cycle_complete(nights_survived: int)

var phase: int = Phase.DAY
var day_index: int = 1
var _timer: float = 0.0
var _completed: bool = false

func reset() -> void:
	phase = Phase.DAY
	day_index = 1
	_timer = DayNight.duration_for(_to_data(phase), day_index)
	_completed = false
	phase_changed.emit(phase, day_index)
	phase_timer_tick.emit(_timer, phase)

func tick(dt: float) -> void:
	if _completed:
		return
	_timer = max(0.0, _timer - dt)
	phase_timer_tick.emit(_timer, phase)
	if _timer <= 0.0:
		_advance_phase()

func is_day() -> bool:
	return phase == Phase.DAY

func is_dusk() -> bool:
	return phase == Phase.DUSK

func is_night() -> bool:
	return phase == Phase.NIGHT

func is_dawn() -> bool:
	return phase == Phase.DAWN

func phase_seconds_left() -> float:
	return _timer

# ── internals ─────────────────────────────────────────────────────────

func _advance_phase() -> void:
	match phase:
		Phase.DAY:
			_set_phase(Phase.DUSK)
		Phase.DUSK:
			_set_phase(Phase.NIGHT)
		Phase.NIGHT:
			_set_phase(Phase.DAWN)
		Phase.DAWN:
			# Dawn ending: we just survived night `day_index`. If that
			# was the MAX_NIGHTS-th night, the run is complete. Otherwise
			# roll over into a new day.
			if day_index >= DayNight.MAX_NIGHTS:
				_completed = true
				cycle_complete.emit(DayNight.MAX_NIGHTS)
				return
			day_index += 1
			_set_phase(Phase.DAY)

func _set_phase(new_phase: int) -> void:
	phase = new_phase
	# When dawn ends and we roll into a new day_index, the day_index
	# bump in _advance_phase already happened; the cycle_complete check
	# is also handled there. Here we just reset the timer for the new
	# phase and announce. Pass day_index so per-round tuning in
	# data/waves.gd applies (BUF-115).
	_timer = DayNight.duration_for(_to_data(phase), day_index)
	# When dawn ends WITHOUT rolling over (because we just hit
	# MAX_NIGHTS), _advance_phase set _completed = true and returned
	# before this point — so we don't emit a stale phase here.
	phase_changed.emit(phase, day_index)
	phase_timer_tick.emit(_timer, phase)

func _to_data(p: int) -> int:
	match p:
		Phase.DAY: return DayNight.PHASE_DAY
		Phase.DUSK: return DayNight.PHASE_DUSK
		Phase.NIGHT: return DayNight.PHASE_NIGHT
		Phase.DAWN: return DayNight.PHASE_DAWN
		_: return DayNight.PHASE_DAY
