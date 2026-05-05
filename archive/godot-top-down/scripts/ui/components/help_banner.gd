extends PanelContainer
##
## HelpBanner — bottom-center alert when a teammate has called for help.
## Mirrors `design/src/components.jsx` `HelpBanner` (eyebrow + title +
## actions). M4 wires the trigger; the component ships ready.
##
## Public API:
##   - show_for(calling_hero, responder_hero, eta_seconds)
##   - clear_help()

var _calling_hero: String = ""
var _responder_hero: String = ""
var _eta_seconds: float = 0.0

# Children
var _eyebrow: Label
var _title: Label
var _actions: Label

func _ready() -> void:
	_build()
	_apply_styles()
	visible = false

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(480, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	_eyebrow = Label.new()
	_eyebrow.text = "⚑ HELP REQUEST"
	_eyebrow.add_theme_font_override("font", DesignTokens.font_body_x_bold())
	_eyebrow.add_theme_font_size_override("font_size", 10)
	_eyebrow.add_theme_color_override("font_color", DesignTokens.HELP_LINE)
	col.add_child(_eyebrow)

	_title = Label.new()
	_title.add_theme_font_override("font", DesignTokens.font_display())
	_title.add_theme_font_size_override("font_size", DesignTokens.FS_2XL)
	_title.add_theme_color_override("font_color", DesignTokens.FG_1)
	col.add_child(_title)

	_actions = Label.new()
	_actions.add_theme_font_override("font", DesignTokens.font_body())
	_actions.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	_actions.add_theme_color_override("font_color", DesignTokens.FG_2)
	col.add_child(_actions)

func _apply_styles() -> void:
	var box := DesignTokens.panel_box(
		DesignTokens.HELP_FILL, DesignTokens.RADIUS_3, DesignTokens.HELP_LINE, 1,
	)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	add_theme_stylebox_override("panel", box)

func show_for(calling_hero: String, responder_hero: String, eta_seconds: float) -> void:
	_calling_hero = calling_hero
	_responder_hero = responder_hero
	_eta_seconds = max(0.0, eta_seconds)
	if _title != null:
		var hero_name := calling_hero if calling_hero != "" else "A teammate"
		_title.text = "%s needs you." % hero_name
	if _actions != null:
		var eta_text: String = ""
		if responder_hero != "" and eta_seconds > 0.0:
			eta_text = " · %s moving · ETA %ds" % [responder_hero, int(ceil(eta_seconds))]
		_actions.text = "[G] ping back · [V] call Val%s" % eta_text
	visible = true

func clear_help() -> void:
	visible = false
	_calling_hero = ""
	_responder_hero = ""
	_eta_seconds = 0.0
