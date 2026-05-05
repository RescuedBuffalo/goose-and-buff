extends Control
##
## Single card widget. Reads its content from the card definition + design
## tokens. Drag-drop is handled by the parent hand widget; this script just
## renders and reports its bounding rect.
##
## Identical contract to godot-prototype/scripts/ui/card_widget.gd —
## intentionally shorter (no card-name truncation, no totem letterbox)
## because Phase 1 only ships Buffalo's deck and the card surface is
## rebuilt for hi-fi v3 polish in M3.

const Cards := preload("res://data/cards.gd")

const CARD_SIZE := Vector2(170, 240)

@export var card_id: String = ""

var card: Dictionary
var _affordable: bool = true

func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_id != "":
		card = Cards.get_card(card_id)
	queue_redraw()

func set_card(new_id: String) -> void:
	card_id = new_id
	card = Cards.get_card(card_id)
	queue_redraw()

func set_affordable(can_afford: bool) -> void:
	if can_afford == _affordable:
		return
	_affordable = can_afford
	queue_redraw()

func _draw() -> void:
	if card.is_empty():
		return
	var faction: String = String(card.faction)
	var bg: Color = _kind_background(card.kind)
	if not _affordable:
		bg = Color(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, bg.a)
	var body := Rect2(Vector2.ZERO, CARD_SIZE)
	draw_rect(body, bg, true)
	# Hairline.
	var border_c := DesignTokens.core_color(faction)
	border_c = Color(border_c.r, border_c.g, border_c.b, 0.45 if _affordable else 0.20)
	draw_rect(body, border_c, false, 1.0)
	# Header strip.
	var header_h := 32.0
	var header_rect := Rect2(0.0, 0.0, CARD_SIZE.x, header_h)
	draw_rect(header_rect, DesignTokens.floor_color(faction), true)
	# Card name.
	_draw_label(String(card.name), Vector2(12, 8),
		DesignTokens.ink_color(faction), DesignTokens.FS_MD)
	# Cost pip top-right.
	if int(card.cost) > 0:
		var pip_radius := 12.0
		var pip_pos := Vector2(CARD_SIZE.x - pip_radius - 8.0, pip_radius + 4.0)
		var pip_fill: Color = DesignTokens.HP_CRIT if not _affordable else DesignTokens.GOLD_COIN
		draw_circle(pip_pos, pip_radius, pip_fill)
		draw_circle(pip_pos, pip_radius, DesignTokens.NIGHT_0, false)
		var pip_text_color: Color = DesignTokens.PARCHMENT_0 if not _affordable else DesignTokens.NIGHT_0
		_draw_label(str(int(card.cost)), pip_pos - Vector2(5, 7), pip_text_color, DesignTokens.FS_MD)
	# Portrait wash with totem.
	var portrait_rect := Rect2(10, header_h + 8, CARD_SIZE.x - 20, 90)
	var floor_wash := DesignTokens.floor_color(faction)
	draw_rect(portrait_rect, Color(floor_wash.r, floor_wash.g, floor_wash.b, 0.20), true)
	draw_rect(portrait_rect, border_c, false, 1.0)
	var totem_tex: Texture2D = DesignTokens.totem_texture(faction)
	if totem_tex != null:
		_draw_totem_in_rect(totem_tex, portrait_rect.grow(-6.0))
	# Description.
	var desc_y := portrait_rect.position.y + portrait_rect.size.y + 8.0
	_draw_label_wrapped(String(card.description), Vector2(12, desc_y),
		DesignTokens.FG_2, DesignTokens.FS_SM, CARD_SIZE.x - 24)
	# Flavor.
	var flavor_y := CARD_SIZE.y - 28.0
	_draw_label_wrapped(String(card.flavor), Vector2(12, flavor_y),
		DesignTokens.FG_3, DesignTokens.FS_XS, CARD_SIZE.x - 24)

func _kind_background(kind: String) -> Color:
	match kind:
		"unit": return DesignTokens.NIGHT_1
		"building": return DesignTokens.NIGHT_2
		"ability": return DesignTokens.NIGHT_1
		"resource": return DesignTokens.NIGHT_2
		_: return DesignTokens.NIGHT_1

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_label_wrapped(text: String, pos: Vector2, color: Color, font_size: int, max_w: float) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_multiline_string(font, pos + Vector2(0, font_size), text,
		HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, -1, color)

func _draw_totem_in_rect(tex: Texture2D, rect: Rect2) -> void:
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var fit: float = min(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * fit
	var draw_pos := rect.position + (rect.size - draw_size) * 0.5
	draw_texture_rect(tex, Rect2(draw_pos, draw_size), false, Color.WHITE)
