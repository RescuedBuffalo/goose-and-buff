extends CanvasModulate
##
## Lighting adapter. Tweens the canvas modulate color to follow the
## DayNightCycle. Day reads as warm gold (effectively no tint), dusk
## slate-blue, night near-black-blue, dawn warm gold again.
##
## BUF-146: depth of cold across days. Each successive day's day/dusk/
## night tints push further toward icy-blue, so the world *visibly*
## deepens into winter even though the chunks themselves don't change
## between days. Day 3's day looks crisp, its night looks deep-frozen.
##
## The CanvasModulate node is added by main.gd as a sibling of the
## sector so it tints the floor + entities but not the HUD layer.

const DayNight := preload("res://data/day_night.gd")

# Phase-base tints. Day 1 anchors here; day 2 + day 3 layer in extra
# cold via _cold_overlay_for(day_index). Subdued at day so the warm
# Buffalo palette dominates; stronger at night so the wolves feel
# like a different tonal register.
const TINT_DAY := Color(1.00, 0.98, 0.92, 1.0)
const TINT_DUSK := Color(0.62, 0.66, 0.82, 1.0)
const TINT_NIGHT := Color(0.32, 0.38, 0.58, 1.0)
const TINT_DAWN := Color(0.92, 0.86, 0.78, 1.0)

# Cold overlay direction — pure ice blue. We blend toward this color
# proportional to (day_index - 1) so day 1 stays warm and day 3 is
# noticeably colder.
const COLD_TINT := Color(0.55, 0.78, 1.00, 1.0)

# Cold blend strengths per day, by phase. Tuned so the deepening reads
# at a glance; day 3 night is the coldest moment in the run.
const COLD_BY_DAY := {
	1: {"day": 0.00, "dusk": 0.00, "night": 0.00, "dawn": 0.00},
	2: {"day": 0.10, "dusk": 0.18, "night": 0.22, "dawn": 0.10},
	3: {"day": 0.22, "dusk": 0.34, "night": 0.42, "dawn": 0.22},
}

var _cycle = null
var _last_day_index: int = 1

func bind(cycle) -> void:
	_cycle = cycle
	_cycle.phase_changed.connect(_on_phase_changed)
	# Initialize to whatever phase the cycle is in right now.
	_apply_for_phase(cycle.phase, cycle.day_index, false)

func _on_phase_changed(phase: int, day_index: int) -> void:
	_apply_for_phase(phase, day_index, true)

func _apply_for_phase(phase: int, day_index: int, animate: bool) -> void:
	_last_day_index = day_index
	var target := _tint_for(phase, day_index)
	if animate:
		var t := create_tween()
		t.tween_property(self, "color", target, 0.6)
	else:
		color = target

func _tint_for(phase: int, day_index: int) -> Color:
	var base: Color
	var phase_key: String
	match phase:
		0:
			base = TINT_DAY
			phase_key = "day"
		1:
			base = TINT_DUSK
			phase_key = "dusk"
		2:
			base = TINT_NIGHT
			phase_key = "night"
		3:
			base = TINT_DAWN
			phase_key = "dawn"
		_:
			base = TINT_DAY
			phase_key = "day"
	var weights: Dictionary = COLD_BY_DAY.get(day_index, COLD_BY_DAY[3])
	var amt: float = float(weights.get(phase_key, 0.0))
	if amt <= 0.0:
		return base
	return base.lerp(COLD_TINT, amt)
