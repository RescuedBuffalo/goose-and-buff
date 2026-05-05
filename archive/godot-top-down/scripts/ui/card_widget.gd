extends Control
##
## Single card widget. Reads its content from the card definition + design
## tokens. Drag-drop is handled by the parent hand widget; this script just
## renders and reports its bounding rect.

const Cards := preload("res://data/cards.gd")

const CARD_SIZE := Vector2(176, 248)

@export var card_id: String = ""

var card: Dictionary
# Affordability mirrors the player's current coin against the card cost.
# Defaults to true so a card briefly reads as playable before the hand
# widget pushes the first balance update post-rebuild.
var _affordable: bool = true

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

func set_affordable(can_afford: bool) -> void:
	# Dim the whole card + tint the cost pip red when the player can't pay
	# the cost. Matches the design's `.deploy-card.unaffordable` state in
	# `design/src/components.css`.
	if can_afford == _affordable:
		return
	_affordable = can_afford
	queue_redraw()

func _draw() -> void:
	if card.is_empty():
		return
	var faction := String(card.faction)
	var bg := _kind_background(card.kind)
	# Whole-card dim when unaffordable. Modulate would also work but doing
	# it in-draw keeps drag-drop behavior unchanged (alpha 0 ≠ unclickable).
	if not _affordable:
		bg = Color(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, bg.a)
	# Rounded card body — radius-3 matches the larger HUD panels and reads
	# well at this size. The ink-colored hairline replaces the old chunky
	# 2px outline so cards no longer look like postage stamps.
	var body := Rect2(Vector2.ZERO, CARD_SIZE)
	var card_border := DesignTokens.hero_core_border(faction)
	if not _affordable:
		# Dimmer hairline so the unaffordable card recedes visually.
		card_border = Color(card_border.r, card_border.g, card_border.b, 0.20)
	draw_style_box(DesignTokens.panel_box(bg, DesignTokens.RADIUS_3, card_border, 1), body)
	# Header strip — faction tone. Drawn inside a clipped path so the corners
	# inherit the card's rounding. Cheaper to fake: draw the strip as a
	# rounded rect that only rounds its top corners by overlapping the
	# bottom edge into the card body.
	var header_h := 32.0
	var header_rect := Rect2(0.0, 0.0, CARD_SIZE.x, header_h)
	var header_box := DesignTokens.panel_box(DesignTokens.floor_color(faction), DesignTokens.RADIUS_3)
	header_box.corner_radius_bottom_left = 0
	header_box.corner_radius_bottom_right = 0
	draw_style_box(header_box, header_rect)
	# Card name (sentence case) — clamped to a single line. The cost pip
	# claims the right ~36 px so we cap the name's available width to match.
	var name_max_w: float = CARD_SIZE.x - 14.0 - 40.0
	var name_text := _truncate_to_width(String(card.name), DesignTokens.FS_MD, name_max_w)
	_draw_label(name_text,
		Vector2(14, 7),
		DesignTokens.ink_color(faction), DesignTokens.FS_MD, false)
	# Cost pip top-right. Tints red when the player can't afford the card.
	if int(card.cost) > 0:
		var pip_radius := 13.0
		var pip_pos := Vector2(CARD_SIZE.x - pip_radius - 8.0, pip_radius + 5.0)
		var pip_fill: Color = DesignTokens.HP_CRIT if not _affordable else DesignTokens.GOLD_COIN
		draw_circle(pip_pos, pip_radius, pip_fill)
		draw_circle(pip_pos, pip_radius, DesignTokens.NIGHT_0, false)
		var pip_text_color: Color = DesignTokens.PARCHMENT_0 if not _affordable else DesignTokens.NIGHT_0
		_draw_label(str(int(card.cost)), pip_pos - Vector2(6, 6), pip_text_color, DesignTokens.FS_MD, true)
	# Portrait area — soft floor wash with the faction totem dropped in.
	# The totem itself carries the brand color, so the wash sits a hair
	# behind it (lantern alpha) instead of a solid core slab.
	var portrait_rect := Rect2(10, header_h + 8, CARD_SIZE.x - 20, 92)
	var floor_wash := DesignTokens.floor_color(faction)
	var portrait_bg := Color(floor_wash.r, floor_wash.g, floor_wash.b, 0.16)
	draw_style_box(
		DesignTokens.panel_box(portrait_bg, DesignTokens.RADIUS_2, card_border, 1),
		portrait_rect,
	)
	var totem_tex: Texture2D = DesignTokens.totem_texture(faction)
	if totem_tex != null:
		_draw_totem_in_rect(totem_tex, portrait_rect.grow(-6.0))
	# Description.
	var desc_y := portrait_rect.position.y + portrait_rect.size.y + 8.0
	_draw_label(String(card.description), Vector2(12, desc_y), DesignTokens.FG_2, DesignTokens.FS_SM, false, CARD_SIZE.x - 24)
	# Flavor — italic-by-color (lower contrast). Sits at the bottom inside
	# the rounded corner.
	var flavor_y := CARD_SIZE.y - 30.0
	_draw_label(String(card.flavor), Vector2(12, flavor_y), DesignTokens.FG_3, DesignTokens.FS_XS, false, CARD_SIZE.x - 24)

func _kind_background(kind: String) -> Color:
	match kind:
		"unit": return DesignTokens.NIGHT_1
		"building": return DesignTokens.NIGHT_2
		"ability": return DesignTokens.NIGHT_1
		"resource": return DesignTokens.NIGHT_2
		_: return DesignTokens.NIGHT_1

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int, mono: bool, max_width: float = 0.0) -> void:
	# Param renamed from `size` — Control.size shadowed it under 4.6.
	var font := ThemeDB.fallback_font
	if mono:
		# Tabular numerals for any cost / numeric text.
		font = ThemeDB.fallback_font
	if max_width > 0.0:
		# Draw multi-line with width clamp.
		draw_multiline_string(font, pos + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, max_width, font_size, -1, color)
	else:
		draw_string(font, pos + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _truncate_to_width(text: String, font_size: int, max_width: float) -> String:
	# The card name lives in a single header line; long names like "Production
	# node" used to wrap and squash the cost pip. Trim with an ellipsis so the
	# header stays one row tall regardless of card.
	var font := ThemeDB.fallback_font
	var full_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if full_w <= max_width:
		return text
	var ellipsis := "…"
	var trimmed := text
	while trimmed.length() > 0:
		var candidate := trimmed + ellipsis
		var w: float = font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w <= max_width:
			return candidate
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	return ellipsis

func _draw_totem_in_rect(tex: Texture2D, rect: Rect2) -> void:
	# Letterbox keeps Buffalo (PNG, 240×200) and the SVG totems consistent
	# inside their portrait frame regardless of source aspect ratio.
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var fit: float = min(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * fit
	var draw_pos := rect.position + (rect.size - draw_size) * 0.5
	draw_texture_rect(tex, Rect2(draw_pos, draw_size), false, Color.WHITE)
