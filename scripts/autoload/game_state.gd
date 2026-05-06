extends Node
##
## Shared run state. Held in a singleton so adapters can read without
## passing references through the scene tree. Pure data — mutated by
## logic modules; rendered by adapters. Same contract as godot-prototype/.

signal phase_changed(phase: String)
signal hero_hp_changed(current: float, maximum: float)
signal core_hp_changed(current: float, maximum: float)
signal retreat_changed(active: bool)
signal signature_cooldown_changed(remaining: float, maximum: float)

enum Phase { PREP, WAVE, DEBRIEF, RUN_COMPLETE, RUN_ENDED }

var phase: int = Phase.PREP
var round_index: int = 1
var hero_id: String = "Buffalo"
var hero_hp: float = 0.0
var hero_hp_max: float = 0.0
var core_hp: float = 0.0
var core_hp_max: float = 0.0
var retreat_mode: bool = false
var signature_cooldown: float = 0.0
var signature_cooldown_max: float = 0.0

# M2 (BUF-145): seed for the current run's procgen world. 0 = "no
# seed configured yet" — main.gd treats that as a signal to roll a
# fresh random one. Set by the run-start screen, read by main.gd.
var run_seed: int = 0

func reset() -> void:
	phase = Phase.PREP
	round_index = 1
	# Route through the setters so every listener (HUD, debug overlay,
	# any future consumer) sees the same zero-state via signals. Direct
	# var assignment kept the autoload's properties in sync but left
	# subscribers stale until something else woke them up.
	set_hero_hp(0.0, 0.0)
	set_core_hp(0.0, 0.0)
	set_retreat(false)
	set_signature_cooldown(0.0, 0.0)

func set_hero(new_hero_id: String) -> void:
	hero_id = new_hero_id

func set_run_config(seed: int, new_hero_id: String) -> void:
	run_seed = seed
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

func set_core_hp(current: float, maximum: float) -> void:
	# Sector mirrors core HP into GameState so the HUD doesn't need a
	# direct sector reference. Without an emit, listeners had to rely on
	# coarse polling. Now a single change notifies everyone.
	core_hp = current
	core_hp_max = maximum
	core_hp_changed.emit(current, maximum)

func set_signature_cooldown(remaining: float, maximum: float) -> void:
	signature_cooldown = remaining
	signature_cooldown_max = maximum
	signature_cooldown_changed.emit(remaining, maximum)

static func phase_name(p: int) -> String:
	match p:
		Phase.PREP: return "prep"
		Phase.WAVE: return "wave"
		Phase.DEBRIEF: return "debrief"
		Phase.RUN_COMPLETE: return "run_complete"
		Phase.RUN_ENDED: return "run_ended"
		_: return "unknown"
