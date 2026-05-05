extends Control
##
## Anchor wrapper. The visual rail is `scripts/ui/components/ability_rail.gd`
## (a PanelContainer that draws the four Q/E/F/R slots per the hi-fi v3
## spec); this script positions one instance at the bottom-left safe inset
## and forwards signal updates from main.gd. Keeps the existing scene wiring
## (`scenes/ui/ability_rail.tscn` is loaded by `main.gd::_build_ui`) intact
## while letting the rendering live in a proper Control hierarchy.

const Component := preload("res://scripts/ui/components/ability_rail.gd")

const SAFE_INSET := 32.0

var _component: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_component = Component.new()
	add_child(_component)
	# Bottom-left, hugging the safe inset. The component sizes itself to its
	# content; we just set offsets and let it grow upward.
	_component.set_anchor(SIDE_LEFT, 0.0, false)
	_component.set_anchor(SIDE_RIGHT, 0.0, false)
	_component.set_anchor(SIDE_TOP, 1.0, false)
	_component.set_anchor(SIDE_BOTTOM, 1.0, false)
	_component.offset_left = SAFE_INSET
	_component.offset_right = SAFE_INSET + 320.0
	_component.offset_top = -120.0
	_component.offset_bottom = -SAFE_INSET
	_component.grow_vertical = Control.GROW_DIRECTION_BEGIN
	GameState.signature_cooldown_changed.connect(_on_cd_changed)

func set_hero(hero_id: String) -> void:
	if _component != null:
		_component.set_hero(hero_id)

func _on_cd_changed(remaining: float, maximum: float) -> void:
	if _component != null:
		_component.set_signature_cooldown(remaining, maximum)
