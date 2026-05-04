extends Node
##
## Shared run state. Held in a singleton so adapters can read without
## passing references through the scene tree. Pure data — mutated by
## logic modules; rendered by adapters.

signal phase_changed(phase: String)
signal hero_hp_changed(current: float, maximum: float)

enum Phase { PREP, WAVE, DEBRIEF, RUN_COMPLETE, RUN_ENDED }

var phase: int = Phase.PREP
var round_index: int = 1
var hero_hp: float = 0.0
var hero_hp_max: float = 0.0
var core_hp: float = 0.0
var core_hp_max: float = 0.0

func reset() -> void:
	phase = Phase.PREP
	round_index = 1
	hero_hp = 0.0
	hero_hp_max = 0.0
	core_hp = 0.0
	core_hp_max = 0.0

func set_phase(new_phase: int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(phase_name(new_phase))

func set_hero_hp(current: float, maximum: float) -> void:
	hero_hp = current
	hero_hp_max = maximum
	hero_hp_changed.emit(current, maximum)

static func phase_name(p: int) -> String:
	match p:
		Phase.PREP: return "prep"
		Phase.WAVE: return "wave"
		Phase.DEBRIEF: return "debrief"
		Phase.RUN_COMPLETE: return "run_complete"
		Phase.RUN_ENDED: return "run_ended"
		_: return "unknown"
