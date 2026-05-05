extends PanelContainer
##
## AbilityRail — bottom-left HUD rail. Mirrors `design/src/components.jsx`
## `AbilityRail`: four slots (Q/E/F/R). v0 only wires Q (signature ability);
## the other three sit empty/locked but the rail still reads as four slots
## per the design spec.
##
## Public API:
##   - set_hero(hero_id)
##   - set_signature_cooldown(remaining, max)

const AbilitySlot := preload("res://scripts/ui/components/ability_slot.gd")
const Heroes := preload("res://data/heroes.gd")

var _hero_id: String = "Buffalo"
var _q_slot: PanelContainer
var _e_slot: PanelContainer
var _f_slot: PanelContainer
var _r_slot: PanelContainer
var _caption: Label

func _ready() -> void:
	_build()
	_apply_styles()
	_apply_hero()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 64)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)

	_q_slot = AbilitySlot.new()
	_e_slot = AbilitySlot.new()
	_f_slot = AbilitySlot.new()
	_r_slot = AbilitySlot.new()
	row.add_child(_q_slot)
	row.add_child(_e_slot)
	row.add_child(_f_slot)
	row.add_child(_r_slot)

	# Signature ability caption — small, dim, just below the rail.
	_caption = Label.new()
	_caption.add_theme_font_override("font", DesignTokens.font_body())
	_caption.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	_caption.add_theme_color_override("font_color", DesignTokens.FG_3)
	col.add_child(_caption)

func _apply_styles() -> void:
	# Rail wrapper — radius-3 panel, hairline. Matches `.ability-rail`.
	var box := DesignTokens.card_panel_box(Color(1, 1, 1, 0.06), 1)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)

func set_hero(hero_id: String) -> void:
	_hero_id = hero_id
	_apply_hero()

func _apply_hero() -> void:
	if _q_slot == null:
		return
	# Q = signature (totem when ready). E/F/R are reserved for M3+ — passed
	# `locked: true` so the slot renders with the dimmed em-dash treatment
	# instead of looking like a broken empty slot.
	_q_slot.configure("Q", _hero_id, true, false)
	_e_slot.configure("E", _hero_id, false, true)
	_f_slot.configure("F", _hero_id, false, true)
	_r_slot.configure("R", _hero_id, false, true)
	# Caption — full hero signature ability name.
	if _caption != null:
		var hero_def: Dictionary = Heroes.ALL.get(_hero_id, Heroes.Buffalo)
		_caption.text = String(hero_def.get("signatureAbility", ""))

func set_signature_cooldown(remaining: float, maximum: float) -> void:
	if _q_slot != null:
		_q_slot.set_cooldown(remaining, maximum)
