extends Node
##
## Shared run state. Held in a singleton so adapters can read without
## passing references through the scene tree. Pure data — mutated by
## logic modules; rendered by adapters.

signal phase_changed(phase: String)
signal hero_hp_changed(current: float, maximum: float)
signal retreat_changed(active: bool)
signal signature_cooldown_changed(remaining: float, maximum: float)

enum Phase { LODGE, PREP, WAVE, DEBRIEF, RUN_COMPLETE, RUN_ENDED }

var phase: int = Phase.PREP
var round_index: int = 1
var hero_id: String = "Buffalo"
var hero_hp: float = 0.0
var hero_hp_max: float = 0.0
var core_hp: float = 0.0
var core_hp_max: float = 0.0
# Retreat mode: when true, units ignore enemies and only follow the leader.
# Toggled by the player; auto-cleared on wave start.
var retreat_mode: bool = false
# Signature ability cooldown — remaining seconds and the cooldown's full
# length. Adapter ticks remaining down each frame; HUD reads to render the
# AbilityRail. Both zero means "ready to cast".
var signature_cooldown: float = 0.0
var signature_cooldown_max: float = 0.0

func reset() -> void:
	phase = Phase.PREP
	round_index = 1
	# hero_id intentionally preserved across reset() — it's set on hero
	# select and survives a "Try again" run. "Change hero" overwrites it
	# explicitly via set_hero().
	hero_hp = 0.0
	hero_hp_max = 0.0
	core_hp = 0.0
	core_hp_max = 0.0
	set_retreat(false)
	set_signature_cooldown(0.0, 0.0)

func set_hero(new_hero_id: String) -> void:
	hero_id = new_hero_id

func set_retreat(active: bool) -> void:
	if retreat_mode == active:
		return
	retreat_mode = active
	retreat_changed.emit(active)

func set_phase(new_phase: int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(phase_name(new_phase))

func set_hero_hp(current: float, maximum: float) -> void:
	hero_hp = current
	hero_hp_max = maximum
	hero_hp_changed.emit(current, maximum)

func set_signature_cooldown(remaining: float, maximum: float) -> void:
	signature_cooldown = remaining
	signature_cooldown_max = maximum
	signature_cooldown_changed.emit(remaining, maximum)

static func phase_name(p: int) -> String:
	match p:
		Phase.LODGE: return "lodge"
		Phase.PREP: return "prep"
		Phase.WAVE: return "wave"
		Phase.DEBRIEF: return "debrief"
		Phase.RUN_COMPLETE: return "run_complete"
		Phase.RUN_ENDED: return "run_ended"
		_: return "unknown"
