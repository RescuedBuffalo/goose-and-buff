extends RefCounted
##
## Adapter glue: translates DayNightCycle phase transitions into
## WaveDirector start/end calls. Lives as an adapter (and not in main.gd)
## so the wiring stays small + grep-able and the wave director's external
## driving surface is documented in one place.
##
## On dusk → night: WaveDirector.start_wave(day_index)
## On night → dawn: WaveDirector.end_wave()

const DayNightCycle := preload("res://scripts/logic/day_night_cycle.gd")

var _cycle = null
var _wave_director: WaveDirector = null
var _last_phase: int = -1

func bind(cycle, wave_director: WaveDirector) -> void:
	_cycle = cycle
	_wave_director = wave_director
	_last_phase = cycle.phase
	_cycle.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(phase: int, day_index: int) -> void:
	# Only act on the *transition*. We ignore the initial DAY emission
	# at reset time — it's the same phase from the gate's perspective.
	var prev := _last_phase
	_last_phase = phase
	if _wave_director == null:
		return
	if prev == DayNightCycle.Phase.DUSK and phase == DayNightCycle.Phase.NIGHT:
		_wave_director.start_wave(day_index)
	elif prev == DayNightCycle.Phase.NIGHT and phase == DayNightCycle.Phase.DAWN:
		_wave_director.end_wave()
