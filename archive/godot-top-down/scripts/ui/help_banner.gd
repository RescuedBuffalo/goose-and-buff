extends Control
##
## Anchor wrapper for the HelpBanner component. Positions the visual banner
## at the bottom-center, just above the Val strip / hand cards.

const Component := preload("res://scripts/ui/components/help_banner.gd")

const SAFE_INSET := 32.0
# Mirrors hud_widget.gd's hand-band height. Cards anchor against the band's
# top so the help banner can sit just above it without competing with the
# hand backdrop.
const HAND_BAND_HEIGHT := 320.0
const BANNER_HEIGHT := 72.0
const BANNER_WIDTH := 520.0

var _component: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_component = Component.new()
	add_child(_component)
	# Compute target bottom: just above the hand band so the alert reads as
	# its own row rather than sharing real estate with the cards.
	var bottom_offset: float = HAND_BAND_HEIGHT + 16.0
	_component.set_anchor(SIDE_LEFT, 0.5, false)
	_component.set_anchor(SIDE_RIGHT, 0.5, false)
	_component.set_anchor(SIDE_TOP, 1.0, false)
	_component.set_anchor(SIDE_BOTTOM, 1.0, false)
	_component.offset_left = -BANNER_WIDTH * 0.5
	_component.offset_right = BANNER_WIDTH * 0.5
	_component.offset_top = -(bottom_offset + BANNER_HEIGHT)
	_component.offset_bottom = -bottom_offset

func show_for(calling_hero: String, responder_hero: String, eta_seconds: float) -> void:
	if _component != null:
		_component.show_for(calling_hero, responder_hero, eta_seconds)
	visible = true

func clear_help() -> void:
	if _component != null:
		_component.clear_help()
	visible = false
