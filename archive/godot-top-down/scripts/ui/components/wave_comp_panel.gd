extends PanelContainer
##
## WaveCompPanel — horizontal top-bar strip that shows the engaged player
## the current wave's composition (Light/Ranged/Heavy counts). Moved out of
## the right-side column to live in the empty space between HeroBadge and
## WavePill, so the panel never competes with the world / core for screen
## real estate. Still derived from `WaveCompPanel` in
## `design/src/components.jsx` — same eyebrow / round name / enemy chips,
## just laid out as a row.
##
## Public API:
##   - show_for(round_index, composition, hero_id)
##   - hide_panel()

const PANEL_WIDTH := 720
const PANEL_HEIGHT := 72.0

var _round_index: int = 1
var _composition: Dictionary = {}
var _hero_id: String = "Buffalo"

# Children
var _eyebrow: Label
var _round_label: Label
var _chips_row: HBoxContainer
var _private_tag: Label

func _ready() -> void:
	_build()
	_apply_styles()
	visible = false

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Outer row: [eyebrow + round name column] [enemy chips] [private tag].
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	# Left column: eyebrow + round name.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size = Vector2(160, 0)
	row.add_child(col)

	_eyebrow = Label.new()
	_eyebrow.text = "WAVE 1 · YOUR SECTOR"
	_eyebrow.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_eyebrow.add_theme_font_size_override("font_size", 10)
	_eyebrow.add_theme_color_override("font_color", DesignTokens.FG_3)
	col.add_child(_eyebrow)

	_round_label = Label.new()
	_round_label.text = "Probe"
	_round_label.add_theme_font_override("font", DesignTokens.font_display())
	_round_label.add_theme_font_size_override("font_size", DesignTokens.FS_LG)
	_round_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	col.add_child(_round_label)

	# Vertical divider — matches the WavePill's divider rule.
	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.12)
	divider.custom_minimum_size = Vector2(1, 36)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(divider)

	# Enemy chip row — `<n>× <kind>` per entry.
	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 14)
	_chips_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chips_row)

	# Private tag — small dim eyebrow tucked at the right.
	_private_tag = Label.new()
	_private_tag.text = "private · visible to you"
	_private_tag.add_theme_font_override("font", DesignTokens.font_body())
	_private_tag.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	_private_tag.add_theme_color_override("font_color", DesignTokens.FG_3)
	_private_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_private_tag)

func _apply_styles() -> void:
	var border := DesignTokens.hero_core_border(_hero_id)
	# Pill-shaped horizontal panel matching the WavePill so the two siblings
	# read as a coherent top-bar pair. Slightly translucent so the world
	# behind shows through.
	var box := DesignTokens.panel_box(
		Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.86),
		int(PANEL_HEIGHT / 2.0), border, 1,
	)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 4)
	box.content_margin_left = 22
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override("panel", box)

func show_for(round_index: int, composition: Dictionary, hero_id: String) -> void:
	_round_index = round_index
	_composition = composition
	_hero_id = hero_id
	_eyebrow.text = "WAVE %d · YOUR SECTOR" % round_index
	_round_label.text = String(composition.get("name", ""))
	# Tint the eyebrow with the hero core (matches the design's `--hero-core`).
	_eyebrow.add_theme_color_override("font_color", DesignTokens.core_color(hero_id))
	# Rebuild chip row.
	for c in _chips_row.get_children():
		c.queue_free()
	var enemies: Array = composition.get("enemies", [])
	for entry in enemies:
		_chips_row.add_child(_make_chip(entry))
	_apply_styles()  # re-tint the border with the hero core
	visible = true

func hide_panel() -> void:
	visible = false

func _make_chip(entry: Dictionary) -> Control:
	# Each chip reads `<n>× <kind>` — the count in tabular mono, kind in body
	# weight. Sits inside the panel's row, no inner stylebox needed.
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := Label.new()
	n.text = "%d×" % int(entry.count)
	n.add_theme_font_override("font", DesignTokens.font_mono_bold())
	n.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	n.add_theme_color_override("font_color", DesignTokens.FG_1)
	chip.add_child(n)
	var k := Label.new()
	k.text = _human_readable(String(entry.type))
	k.add_theme_font_override("font", DesignTokens.font_body())
	k.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	k.add_theme_color_override("font_color", DesignTokens.FG_2)
	chip.add_child(k)
	return chip

func _human_readable(enemy_type: String) -> String:
	if enemy_type.is_empty():
		return ""
	var parts: PackedStringArray = []
	var current := ""
	for i in enemy_type.length():
		var ch := enemy_type[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			parts.append(current)
			current = ""
		current += ch
	parts.append(current)
	if parts.is_empty():
		return enemy_type
	var head: String = parts[0]
	var tail_parts: PackedStringArray = []
	for j in range(1, parts.size()):
		tail_parts.append(parts[j].to_lower())
	if tail_parts.is_empty():
		return head
	return "%s %s" % [head, " ".join(tail_parts)]
