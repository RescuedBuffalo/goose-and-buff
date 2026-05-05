extends Control
##
## Hero select overlay. Shows the three heroes (Goose · Buffalo · Fox in
## canonical order) on a curtain over the play area. Click a card or press
## 1/2/3 to lock in. Emits `hero_selected(hero_id)` and hides — main.gd
## then configures the hero / sector and starts the run.
##
## All visuals come from `DesignTokens` (faction colors per card) and the
## `data/heroes.gd` dictionaries (stats, role, flavor). Layout numbers are
## tuned against `design/wireframes/Wireframes.html` surface 01 — keep
## them in sync if the wireframe moves.

const Heroes := preload("res://data/heroes.gd")

signal hero_selected(hero_id: String)

const CARD_SIZE := Vector2(280, 380)
const CARD_GAP := 24.0
const CARDS_TOP_Y := 200.0

# Per-hero totem assets. Buffalo ships as a PNG; Goose / Fox as SVG.
const TOTEM_PATHS := {
	"Buffalo": "res://assets/totems/buffalo.png",
	"Goose": "res://assets/totems/goose.svg",
	"Fox": "res://assets/totems/fox.svg",
}

const TOTEM_SCALE := {
	"Buffalo": Vector2(0.55, 0.55),
	"Goose": Vector2(0.85, 0.85),
	"Fox": Vector2(0.85, 0.85),
}

# Debug "reset save" pill in the bottom-right footer corner. Sized so the
# label "Reset save (Shift-click)" reads at FS_XS without crowding.
const RESET_BTN_SIZE := Vector2(220, 28)
const RESET_BTN_MARGIN := 16.0

var _hover_hero_id: String = ""
var _totem_textures: Dictionary = {}
# Toggled in the footer pill on hover so the player can see they're targeting
# the debug button. Independent from the hero-card hover state.
var _hover_reset: bool = false
# Brief flash text shown after a reset. Cleared on next open().
var _reset_notice: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_preload_totems()

func open() -> void:
	visible = true
	_hover_hero_id = ""
	_hover_reset = false
	_reset_notice = ""
	queue_redraw()
	# Make sure we capture clicks even if a sibling control is on top.
	move_to_front()

func close() -> void:
	visible = false
	_hover_hero_id = ""

func _preload_totems() -> void:
	for hid in TOTEM_PATHS.keys():
		var tex: Texture2D = load(TOTEM_PATHS[hid])
		if tex:
			_totem_textures[hid] = tex

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prior := _hover_hero_id
		var prior_reset := _hover_reset
		_hover_hero_id = _hero_id_at(event.position)
		_hover_reset = _reset_rect().has_point(event.position)
		if prior != _hover_hero_id or prior_reset != _hover_reset:
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _reset_rect().has_point(event.position):
			# Shift-click guards a destructive debug action without needing a
			# confirm dialog. The label tells the player which modifier to use.
			if event.shift_pressed:
				_perform_reset()
			else:
				_reset_notice = "Hold Shift and click to confirm."
				queue_redraw()
			return
		var hid := _hero_id_at(event.position)
		if hid != "":
			_lock_in(hid)

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcuts mirror the pings on the wireframe (key 1/2/3).
	# Routed through _unhandled_input rather than _gui_input because the
	# latter only fires for the focused Control — this overlay never
	# grabs focus, and we don't want to depend on it.
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_lock_in(Heroes.ORDER[0])
			get_viewport().set_input_as_handled()
		KEY_2:
			_lock_in(Heroes.ORDER[1])
			get_viewport().set_input_as_handled()
		KEY_3:
			_lock_in(Heroes.ORDER[2])
			get_viewport().set_input_as_handled()

func _lock_in(hero_id: String) -> void:
	if not Heroes.ALL.has(hero_id):
		return
	hero_selected.emit(hero_id)
	close()

func _perform_reset() -> void:
	SaveSystem.reset()
	_reset_notice = "Save reset. Run #1 ahead."
	queue_redraw()

func _hero_id_at(local_pos: Vector2) -> String:
	for i in Heroes.ORDER.size():
		var hid: String = Heroes.ORDER[i]
		if _card_rect(i).has_point(local_pos):
			return hid
	return ""

func _card_rect(index: int) -> Rect2:
	var total_w := float(Heroes.ORDER.size()) * CARD_SIZE.x \
		+ float(Heroes.ORDER.size() - 1) * CARD_GAP
	var start_x := (size.x - total_w) * 0.5
	var x := start_x + float(index) * (CARD_SIZE.x + CARD_GAP)
	return Rect2(Vector2(x, CARDS_TOP_Y), CARD_SIZE)

func _draw() -> void:
	# Curtain — same Night-0 wash the end screen uses, slightly heavier so
	# the cards read as the focus.
	draw_rect(Rect2(Vector2.ZERO, size),
		Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.92), true)
	_draw_header()
	for i in Heroes.ORDER.size():
		_draw_card(i, Heroes.ORDER[i])
	_draw_footer()

func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	# Persisted run counter drives the eyebrow — shows the upcoming run.
	var eyebrow := "RUN #%d" % (SaveSystem.get_run_count() + 1)
	var headline := "Pick your post."
	var sub := "Three sectors. One companion. We hold the line together."
	var center_x := size.x * 0.5
	var top_y := 60.0
	var eyebrow_w := font.get_string_size(eyebrow, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS).x
	draw_string(font, Vector2(center_x - eyebrow_w * 0.5, top_y),
		eyebrow, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	var headline_w := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL).x
	draw_string(font, Vector2(center_x - headline_w * 0.5, top_y + 56),
		headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL, DesignTokens.FG_1)
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
	draw_string(font, Vector2(center_x - sub_w * 0.5, top_y + 92),
		sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, DesignTokens.FG_2)

func _draw_card(index: int, hero_id: String) -> void:
	var hero: Dictionary = Heroes.ALL[hero_id]
	var rect := _card_rect(index)
	var is_hover := _hover_hero_id == hero_id
	var floor_color := DesignTokens.floor_color(hero_id)
	var core_color := DesignTokens.core_color(hero_id)
	var ink_color := DesignTokens.ink_color(hero_id)
	# Card body — parchment fill, faction outline that strengthens on hover.
	draw_rect(rect, DesignTokens.PARCHMENT_0, true)
	var border_w := 4.0 if is_hover else 2.0
	draw_rect(rect, core_color, false, border_w)
	# Totem zone — a faction-floor band across the top with the totem image
	# centered inside it.
	var totem_h := 168.0
	var totem_zone := Rect2(rect.position, Vector2(rect.size.x, totem_h))
	draw_rect(totem_zone, floor_color, true)
	draw_line(Vector2(totem_zone.position.x, totem_zone.position.y + totem_h),
		Vector2(totem_zone.position.x + totem_zone.size.x, totem_zone.position.y + totem_h),
		core_color, 2.0)
	# Eyebrow tag — "Totem · Goose"
	var font := ThemeDB.fallback_font
	var tag := "TOTEM · %s" % hero.name
	draw_string(font, totem_zone.position + Vector2(14, 22),
		tag, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, ink_color)
	# Totem image, centered in the zone.
	if _totem_textures.has(hero_id):
		var tex: Texture2D = _totem_textures[hero_id]
		var scale: Vector2 = TOTEM_SCALE.get(hero_id, Vector2(0.65, 0.65))
		var tex_size := tex.get_size() * scale
		var tex_pos := totem_zone.position + (totem_zone.size - tex_size) * 0.5
		draw_texture_rect(tex, Rect2(tex_pos, tex_size), false)
	# Body — name, role, flavor, stats.
	var body_x := rect.position.x + 18.0
	var body_y := rect.position.y + totem_h + 16.0
	draw_string(font, Vector2(body_x, body_y + DesignTokens.FS_2XL),
		hero.name, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_2XL, DesignTokens.PARCHMENT_INK)
	draw_string(font, Vector2(body_x, body_y + DesignTokens.FS_2XL + 22),
		hero.role, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.NIGHT_3)
	# Flavor wraps to two lines max — draw_multiline_string handles wrapping.
	draw_multiline_string(font, Vector2(body_x, body_y + DesignTokens.FS_2XL + 50),
		hero.flavor, HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 36.0, DesignTokens.FS_SM, 3, DesignTokens.NIGHT_2)
	# Stats row at the bottom — HP, Speed, signature ability name.
	var stats_y := rect.position.y + rect.size.y - 84.0
	_draw_stat(Vector2(body_x, stats_y), "HP", str(int(hero.baseHealth)))
	_draw_stat(Vector2(body_x + 88, stats_y), "Speed", str(int(hero.moveSpeed)))
	_draw_stat(Vector2(body_x + 176, stats_y), "Signature", hero.signatureAbility)
	# CTA strip — a faction-core ribbon at the bottom.
	var cta_h := 36.0
	var cta_rect := Rect2(rect.position + Vector2(0, rect.size.y - cta_h),
		Vector2(rect.size.x, cta_h))
	draw_rect(cta_rect, core_color, true)
	var cta := "Lock in"
	var cta_w := font.get_string_size(cta, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
	draw_string(font, cta_rect.position + Vector2((cta_rect.size.x - cta_w) * 0.5, 24),
		cta, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, ink_color)
	# Keyboard ping — the wireframe puts a small "key 1" tag at top-right.
	var ping := "key %d" % (index + 1)
	var ping_w := font.get_string_size(ping, HORIZONTAL_ALIGNMENT_RIGHT, -1, DesignTokens.FS_XS).x
	draw_string(font, rect.position + Vector2(rect.size.x - ping_w - 12, 22),
		ping, HORIZONTAL_ALIGNMENT_RIGHT, -1, DesignTokens.FS_XS, ink_color)

func _draw_stat(pos: Vector2, label: String, value: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, DesignTokens.FS_XS),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.NIGHT_3)
	draw_string(font, pos + Vector2(0, DesignTokens.FS_XS + 22),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_MD, DesignTokens.PARCHMENT_INK)

func _draw_footer() -> void:
	var font := ThemeDB.fallback_font
	var hint := "Click a card or press 1 / 2 / 3 to lock in."
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_SM).x
	draw_string(font, Vector2((size.x - hint_w) * 0.5, size.y - 56),
		hint, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_SM, DesignTokens.FG_3)
	_draw_reset_button(font)
	if _reset_notice != "":
		var notice_w := font.get_string_size(_reset_notice, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS).x
		draw_string(font, Vector2((size.x - notice_w) * 0.5, size.y - 30),
			_reset_notice, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS, DesignTokens.FG_2)

func _reset_rect() -> Rect2:
	# Anchored bottom-right so it sits out of the way of the hero cards but
	# stays reachable on any window size.
	var pos := Vector2(size.x - RESET_BTN_SIZE.x - RESET_BTN_MARGIN,
		size.y - RESET_BTN_SIZE.y - RESET_BTN_MARGIN)
	return Rect2(pos, RESET_BTN_SIZE)

func _draw_reset_button(font: Font) -> void:
	var rect := _reset_rect()
	var fill := DesignTokens.NIGHT_2 if _hover_reset else DesignTokens.NIGHT_1
	var border := DesignTokens.FG_3 if _hover_reset else DesignTokens.NIGHT_3
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 1.0)
	var label := "Reset save (Shift-click)"
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS).x
	draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 5),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS, DesignTokens.FG_2)
