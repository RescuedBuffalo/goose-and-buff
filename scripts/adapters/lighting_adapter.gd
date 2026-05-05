extends CanvasModulate
##
## Lighting adapter. Tweens the canvas modulate color to follow the
## DayNightCycle. Day reads as warm gold (effectively no tint), dusk
## slate-blue, night near-black-blue, dawn warm gold again.
##
## The CanvasModulate node is added by main.gd as a sibling of the
## sector so it tints the floor + entities but not the HUD layer.

const DayNight := preload("res://data/day_night.gd")

# Phase tints. Subdued at day so the warm Buffalo palette dominates;
# stronger at night so the wolves feel like a different tonal register.
const TINT_DAY := Color(1.00, 0.98, 0.92, 1.0)
const TINT_DUSK := Color(0.62, 0.66, 0.82, 1.0)
const TINT_NIGHT := Color(0.32, 0.38, 0.58, 1.0)
const TINT_DAWN := Color(0.92, 0.86, 0.78, 1.0)

var _cycle = null

func bind(cycle) -> void:
	_cycle = cycle
	_cycle.phase_changed.connect(_on_phase_changed)
	# Initialize to whatever phase the cycle is in right now.
	_apply_for_phase(cycle.phase, false)

func _on_phase_changed(phase: int, _day_index: int) -> void:
	_apply_for_phase(phase, true)

func _apply_for_phase(phase: int, animate: bool) -> void:
	var target := _tint_for(phase)
	if animate:
		var t := create_tween()
		t.tween_property(self, "color", target, 0.6)
	else:
		color = target

func _tint_for(phase: int) -> Color:
	match phase:
		0: return TINT_DAY
		1: return TINT_DUSK
		2: return TINT_NIGHT
		3: return TINT_DAWN
		_: return TINT_DAY
