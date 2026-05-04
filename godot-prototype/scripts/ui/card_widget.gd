extends Control
##
## Single card widget. Reads its content from the card definition + design
## tokens. Drag-drop is handled by the parent hand widget; this script just
## renders and reports its bounding rect.

const Cards := preload("res://data/cards.gd")

const CARD_SIZE := Vector2(176, 248)

@export var card_id: String = ""

var card: Dictionary

func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	# Hand widget owns drag-drop input; cards are display-only.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_id != "":
		card = Cards.get_card(card_id)
	queue_redraw()

func set_card(new_id: String) -> void:
	card_id = new_id
	card = Cards.get_card(card_id)
	queue_redraw()

func _draw() -> void:
	if card.is_empty():
		return
	var faction := String(card.faction)
	var ink := DesignTokens.ink_color(faction)
	var bg := _kind_background(card.kind)
	# Card body.
	var body := Rect2(Vector2.ZERO, CARD_SIZE)
	draw_rect(body, bg, true)
	draw_rect(body, ink, false, 2.0)
	# Header strip — faction tone.
	var header_h := 36.0
	draw_rect(Rect2(0, 0, CARD_SIZE.x, header_h), DesignTokens.floor_color(faction), true)
	# Cost pip top-right.
	if int(card.cost) > 0:
		var pip_radius := 14.0
		var pip_pos := Vector2(CARD_SIZE.x - pip_radius - 8.0, pip_radius + 8.0)
		draw_circle(pip_pos, pip_radius, DesignTokens.GOLD_COIN)
		draw_circle(pip_pos, pip_radius, DesignTokens.NIGHT_0, false)
		_draw_label(str(int(card.cost)), pip_pos - Vector2(6, 6), DesignTokens.NIGHT_0, DesignTokens.FS_MD, true)
	# Faction totem dot top-left (placeholder for the SVG mark).
	var mark_pos := Vector2(20, 18)
	draw_circle(mark_pos, 10.0, DesignTokens.core_color(faction))
	# Portrait area — gradient placeholder.
	var portrait_rect := Rect2(8, header_h + 8, CARD_SIZE.x - 16, 96)
	draw_rect(portrait_rect, DesignTokens.core_color(faction), true)
	draw_rect(portrait_rect, ink, false, 1.0)
	# Centered card name in the portrait area.
	_draw_label(String(card.name), portrait_rect.position + Vector2(10, 36), DesignTokens.PARCHMENT_0, DesignTokens.FS_LG, false)
	# Description.
	var desc_y := portrait_rect.position.y + portrait_rect.size.y + 10.0
	_draw_label(String(card.description), Vector2(10, desc_y), DesignTokens.FG_2, DesignTokens.FS_SM, false, CARD_SIZE.x - 20)
	# Flavor.
	var flavor_y := CARD_SIZE.y - 28.0
	_draw_label(String(card.flavor), Vector2(10, flavor_y), DesignTokens.FG_3, DesignTokens.FS_SM, false, CARD_SIZE.x - 20)

func _kind_background(kind: String) -> Color:
	match kind:
		"unit": return DesignTokens.NIGHT_1
		"building": return DesignTokens.NIGHT_2
		"ability": return DesignTokens.NIGHT_1
		"resource": return DesignTokens.NIGHT_2
		_: return DesignTokens.NIGHT_1

func _draw_label(text: String, pos: Vector2, color: Color, size: int, mono: bool, max_width: float = 0.0) -> void:
	var font := ThemeDB.fallback_font
	if mono:
		# Tabular numerals for any cost / numeric text.
		font = ThemeDB.fallback_font
	if max_width > 0.0:
		# Draw multi-line with width clamp.
		draw_multiline_string(font, pos + Vector2(0, size), text, HORIZONTAL_ALIGNMENT_LEFT, max_width, size, -1, color)
	else:
		draw_string(font, pos + Vector2(0, size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
