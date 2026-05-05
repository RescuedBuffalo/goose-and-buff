extends Control
##
## Anchor wrapper for the WaveCompPanel component. Now anchored in the
## TOP bar — centered horizontally between the HeroBadge/Balance column on
## the left and the WavePill on the right — so it never overlaps the world
## or the core. Forwards `show_for` / `hide_panel` from main.gd.

const Component := preload("res://scripts/ui/components/wave_comp_panel.gd")

const SAFE_INSET := 32.0
const TOP_BAR_HEIGHT := 72.0
const PANEL_WIDTH := 720.0
# Reserve room either side for the badge column (left) and wave pill (right)
# so the comp panel always sits in the middle band.
const LEFT_RESERVE := 540.0   # HeroBadge (360) + gap (12) + BalanceChip (132) + 36 breathing room
const RIGHT_RESERVE := 472.0  # WavePill (440) + 32 safe inset

var _component: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_component = Component.new()
	add_child(_component)
	# Anchor across the full top: left edge after the badge column, right
	# edge before the wave pill. Component sizes itself; we just bound it.
	_component.set_anchor(SIDE_LEFT, 0.0, false)
	_component.set_anchor(SIDE_RIGHT, 1.0, false)
	_component.set_anchor(SIDE_TOP, 0.0, false)
	_component.set_anchor(SIDE_BOTTOM, 0.0, false)
	_component.offset_left = LEFT_RESERVE
	_component.offset_right = -RIGHT_RESERVE
	_component.offset_top = SAFE_INSET
	_component.offset_bottom = SAFE_INSET + TOP_BAR_HEIGHT

func show_for(round_index: int, composition: Dictionary, hero_id: String) -> void:
	if _component != null:
		_component.show_for(round_index, composition, hero_id)
	visible = true

func hide_panel() -> void:
	if _component != null:
		_component.hide_panel()
	visible = false
