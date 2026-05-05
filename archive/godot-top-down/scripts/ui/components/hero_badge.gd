extends PanelContainer
##
## HeroBadge — top-left HUD card. Mirrors `design/src/components.jsx`
## `HeroBadge` 1:1 (totem puck + name row + HP row), and the styles in
## `design/src/components.css` (`.hero-badge`, `.hb-stripe`, `.hb-name`,
## `.hb-hp-track`, `.hb-hp-fill`, `.hb-pip-combat`).
##
## Public API:
##   - set_hero(hero_id)      → swap totem, palette, default HP max
##   - set_hp(current, max)   → live HP update
##   - set_combat(active)     → light the IN COMBAT pip during waves
##   - set_downed(active)     → grayscale / dim
##
## Owns no signals — purely presentational. The HUD coordinator drives it.

const TotemHelper := preload("res://scripts/ui/components/totem_image.gd")

# Visual constants — match `--space-*` and `--radius-*` from tokens.css.
const STRIPE_W := 4
const PUCK_SIZE := 48
const HP_BAR_HEIGHT := 8

var _hero_id: String = "Buffalo"
var _hp: float = 0.0
var _hp_max: float = 0.0
var _combat: bool = false
var _downed: bool = false

# Children built once in _ready, then mutated.
var _stripe: ColorRect
var _puck: PanelContainer
var _totem: Control  # TotemImage instance (Control with custom _draw)
var _name_label: Label
var _combat_pip: Label
var _hp_track: PanelContainer
var _hp_fill: Panel
var _hp_label: Label

func _ready() -> void:
	_build()
	_apply_styles()
	_refresh()

func _build() -> void:
	# Outer panel — handled by `add_theme_stylebox_override("panel", ...)` in
	# _apply_styles. We just lay out the row inside.
	custom_minimum_size = Vector2(320, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Left accent stripe — sits flush against the panel's rounded corner via
	# clip_contents. Drawn as a child of `self` so it overlays the StyleBox.
	_stripe = ColorRect.new()
	_stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_stripe.size_flags_horizontal = 0
	_stripe.custom_minimum_size = Vector2(STRIPE_W, 0)
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stripe)

	# Row body
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)

	# Totem puck.
	_puck = PanelContainer.new()
	_puck.custom_minimum_size = Vector2(PUCK_SIZE, PUCK_SIZE)
	_puck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_puck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_puck)

	_totem = TotemHelper.new()
	_totem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_totem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_puck.add_child(_totem)

	# Center column — name row + hp row.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	# Name row: name on the left, combat pip on the right when active.
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 8)
	col.add_child(name_row)

	_name_label = Label.new()
	_name_label.text = _hero_id
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_name_label.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	_name_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	name_row.add_child(_name_label)

	_combat_pip = Label.new()
	_combat_pip.text = "IN COMBAT"
	_combat_pip.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_combat_pip.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	_combat_pip.add_theme_color_override("font_color", DesignTokens.PIP_COMBAT_FG)
	_combat_pip.visible = false
	name_row.add_child(_combat_pip)

	# HP row: rounded track filled by an inner panel; numeric HP at the end.
	var hp_row := HBoxContainer.new()
	hp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_theme_constant_override("separation", 8)
	col.add_child(hp_row)

	_hp_track = PanelContainer.new()
	_hp_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_track.custom_minimum_size = Vector2(0, HP_BAR_HEIGHT)
	_hp_track.clip_contents = true
	hp_row.add_child(_hp_track)

	_hp_fill = Panel.new()
	_hp_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_hp_fill.size_flags_horizontal = 0
	_hp_track.add_child(_hp_fill)

	_hp_label = Label.new()
	_hp_label.text = "0 / 0"
	_hp_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_hp_label.add_theme_font_override("font", DesignTokens.font_mono_bold())
	_hp_label.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	_hp_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	hp_row.add_child(_hp_label)

func _apply_styles() -> void:
	# Outer card.
	var box := DesignTokens.card_panel_box(DesignTokens.hero_core_border(_hero_id), 1)
	# Bias content rightward so the 4px stripe doesn't get covered by the puck.
	box.content_margin_left = 16
	add_theme_stylebox_override("panel", box)
	# Stripe color follows the hero accent.
	if _stripe != null:
		_stripe.color = DesignTokens.hero_stripe_color(_hero_id)
	# Puck — soft hero-lantern wash.
	var puck_box := DesignTokens.panel_box(
		DesignTokens.lantern_color(_hero_id), DesignTokens.RADIUS_2,
		Color(1.0, 1.0, 1.0, 0.10), 1,
	)
	puck_box.content_margin_left = 4
	puck_box.content_margin_right = 4
	puck_box.content_margin_top = 4
	puck_box.content_margin_bottom = 4
	if _puck != null:
		_puck.add_theme_stylebox_override("panel", puck_box)
	if _totem != null:
		_totem.set_faction(_hero_id)
	# HP track + fill.
	if _hp_track != null:
		_hp_track.add_theme_stylebox_override("panel", DesignTokens.hp_track_box())
	# Combat pip pill.
	if _combat_pip != null:
		_combat_pip.add_theme_stylebox_override("normal", DesignTokens.combat_pip_box())

func set_hero(hero_id: String) -> void:
	if hero_id == _hero_id:
		return
	_hero_id = hero_id
	if _name_label != null:
		_name_label.text = hero_id
	if _totem != null:
		_totem.set_faction(hero_id)
	# Re-skin the parts that depend on faction palette.
	_apply_styles()
	_refresh()

func set_hp(current: float, hp_max: float) -> void:
	_hp = max(0.0, current)
	_hp_max = max(0.0, hp_max)
	_refresh()

func set_combat(active: bool) -> void:
	if active == _combat:
		return
	_combat = active
	if _combat_pip != null:
		_combat_pip.visible = active

func set_downed(active: bool) -> void:
	_downed = active
	modulate = Color(1, 1, 1, 0.55) if active else Color(1, 1, 1, 1)
	_refresh()

func _refresh() -> void:
	if _hp_label == null or _hp_fill == null or _hp_track == null:
		return
	var ratio: float = 0.0 if _hp_max <= 0.0 else clamp(_hp / _hp_max, 0.0, 1.0)
	# Fill width as a fraction of the track. Use call_deferred so the track
	# has been laid out at least once before we sample its size.
	_apply_hp_fill.call_deferred(ratio)
	if _downed or _hp <= 0.0 and _hp_max > 0.0:
		_hp_label.text = "Downed"
		_hp_label.add_theme_color_override("font_color", DesignTokens.HP_CRIT)
	else:
		_hp_label.text = "%d / %d" % [int(_hp), int(_hp_max)]
		_hp_label.add_theme_color_override("font_color", DesignTokens.FG_1)
	# Fill color follows HP ratio.
	var fill_color: Color = DesignTokens.HP_CRIT if _downed else DesignTokens.hp_color(ratio)
	_hp_fill.add_theme_stylebox_override("panel", DesignTokens.hp_fill_box(fill_color))

func _apply_hp_fill(ratio: float) -> void:
	if _hp_track == null or _hp_fill == null:
		return
	var track_w: float = _hp_track.size.x
	if track_w <= 0.0:
		# Layout hasn't run yet; defer one more frame.
		_apply_hp_fill.call_deferred(ratio)
		return
	_hp_fill.offset_left = 0
	_hp_fill.offset_right = track_w * ratio
	_hp_fill.offset_top = 0
	_hp_fill.offset_bottom = HP_BAR_HEIGHT
