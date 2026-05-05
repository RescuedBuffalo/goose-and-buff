extends Control
##
## The Lodge's "Card unlocks" station — meta-progression UI shown over the
## warm room (BUF-113). Two columns per hero:
##   1. Card unlocks: locked cards in this hero's pool with a token price.
##      Click to spend tokens and add the card to the unlocked pool.
##   2. Deck swaps: unlocked cards with a single toggle that swaps them
##      in for the starter card their `replaces` field names. Toggling
##      again swaps them back out.
##
## Hero tabs at the top scope both columns to one hero at a time. Token
## balance and per-hero unlocked count surface in the header so the player
## doesn't have to leave the screen to see their progress.
##
## Visual language follows hero_select.gd / lodge.gd — Night-0 curtain,
## parchment card bodies, faction core/floor accents on the active tab.
## All values pulled from DesignTokens; hero ordering from `Heroes.ORDER`
## so it matches the hero-select wireframe's muscle memory.
##
## State lives in SaveSystem — this screen reads + mutates and redraws on
## the `meta_changed` signal. Closing returns to the Lodge underneath.

const Heroes := preload("res://data/heroes.gd")
const Cards := preload("res://data/cards.gd")

signal closed()

const HERO_TAB_W := 168.0
const HERO_TAB_H := 44.0
const HERO_TAB_GAP := 12.0
const HERO_TABS_TOP := 152.0

const ROW_H := 84.0
const ROW_GAP := 8.0
const BODY_TOP := 232.0

const ACTION_W := 200.0
const ACTION_H := 56.0

const CLOSE_W := 200.0
const CLOSE_H := 48.0

var _selected_hero: String = "Buffalo"
# Cached row rects for hit-testing. Each row carries the card_id it represents
# and the action it triggers when clicked. Rebuilt every redraw so the layout
# stays in sync after unlock/swap actions reshuffle the sections.
var _row_actions: Array = []  # Array of {rect: Rect2, kind: String, card_id: String}
var _close_rect: Rect2 = Rect2()
var _hero_tab_rects: Dictionary = {}
var _toast: String = ""
var _toast_until_msec: int = 0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Default the tab to whoever the player just played as — keeps continuity
	# with the run that just ended. Falls through to Buffalo if hero_id is
	# blank somehow (shouldn't happen post-hero-select, but harmless).
	if GameState.hero_id != "":
		_selected_hero = GameState.hero_id
	SaveSystem.meta_changed.connect(_on_meta_changed)

func open() -> void:
	if GameState.hero_id != "":
		_selected_hero = GameState.hero_id
	visible = true
	move_to_front()
	queue_redraw()

func close() -> void:
	visible = false
	closed.emit()

func _process(_delta: float) -> void:
	# Keep the toast countdown ticking without forcing a redraw every frame —
	# only invalidate when the message actually expires.
	if _toast != "" and Time.get_ticks_msec() >= _toast_until_msec:
		_toast = ""
		queue_redraw()

func _on_meta_changed() -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			KEY_1:
				_select_hero(Heroes.ORDER[0])
				get_viewport().set_input_as_handled()
			KEY_2:
				_select_hero(Heroes.ORDER[1])
				get_viewport().set_input_as_handled()
			KEY_3:
				_select_hero(Heroes.ORDER[2])
				get_viewport().set_input_as_handled()

func _handle_click(pos: Vector2) -> void:
	if _close_rect.has_point(pos):
		close()
		return
	for hid in _hero_tab_rects.keys():
		if _hero_tab_rects[hid].has_point(pos):
			_select_hero(hid)
			return
	for entry in _row_actions:
		if entry.rect.has_point(pos):
			_perform_action(entry.kind, entry.card_id)
			return

func _select_hero(hero_id: String) -> void:
	if not Heroes.ALL.has(hero_id) or hero_id == _selected_hero:
		return
	_selected_hero = hero_id
	queue_redraw()

func _perform_action(kind: String, card_id: String) -> void:
	match kind:
		"unlock":
			if SaveSystem.purchase_unlock(_selected_hero, card_id):
				_show_toast("Unlocked.")
			elif not SaveSystem.can_afford_unlock():
				_show_toast("Not enough tokens.")
		"toggle_swap":
			SaveSystem.toggle_card_in_deck(_selected_hero, card_id)
			# Redraw is driven by the meta_changed signal — no toast needed,
			# the row label flips immediately and that's the feedback.

func _show_toast(text: String) -> void:
	_toast = text
	_toast_until_msec = Time.get_ticks_msec() + 1600
	queue_redraw()

# ── Drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	_row_actions.clear()
	_hero_tab_rects.clear()
	# Curtain — slightly heavier than hero_select's wash; the Lodge is meant
	# to feel like a calmer interior space.
	draw_rect(Rect2(Vector2.ZERO, size),
		Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.94), true)
	_draw_header()
	_draw_hero_tabs()
	_draw_body()
	_draw_close_button()
	_draw_toast()

func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	var center_x := size.x * 0.5
	var eyebrow := "CARD UNLOCKS"
	var headline := "The chest."
	var sub := "Spend tokens to unlock cards. Swap them into the deck for next run."
	var eyebrow_w := font.get_string_size(eyebrow, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS).x
	draw_string(font, Vector2(center_x - eyebrow_w * 0.5, 56),
		eyebrow, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	var headline_w := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL).x
	draw_string(font, Vector2(center_x - headline_w * 0.5, 100),
		headline, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_3XL, DesignTokens.FG_1)
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_SM).x
	draw_string(font, Vector2(center_x - sub_w * 0.5, 128),
		sub, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_SM, DesignTokens.FG_2)
	# Token balance — top-right, gold-coin tinted.
	var balance := "%d tokens" % SaveSystem.get_meta_currency()
	var balance_w := font.get_string_size(balance, HORIZONTAL_ALIGNMENT_RIGHT, -1, DesignTokens.FS_LG).x
	draw_string(font, Vector2(size.x - balance_w - 48, 80),
		balance, HORIZONTAL_ALIGNMENT_RIGHT, -1, DesignTokens.FS_LG, DesignTokens.GOLD_COIN)

func _draw_hero_tabs() -> void:
	var font := ThemeDB.fallback_font
	var total_w := float(Heroes.ORDER.size()) * HERO_TAB_W \
		+ float(Heroes.ORDER.size() - 1) * HERO_TAB_GAP
	var start_x := (size.x - total_w) * 0.5
	for i in Heroes.ORDER.size():
		var hid: String = Heroes.ORDER[i]
		var x := start_x + float(i) * (HERO_TAB_W + HERO_TAB_GAP)
		var rect := Rect2(x, HERO_TABS_TOP, HERO_TAB_W, HERO_TAB_H)
		_hero_tab_rects[hid] = rect
		var is_active := hid == _selected_hero
		var core := DesignTokens.core_color(hid)
		var fill := core if is_active else DesignTokens.NIGHT_2
		draw_rect(rect, fill, true)
		draw_rect(rect, core, false, 2.0 if is_active else 1.0)
		var label := "%s · %d / %d" % [
			hid, _unlocked_count(hid), Cards.UNLOCK_POOLS.get(hid, []).size()
		]
		var ink := DesignTokens.ink_color(hid) if is_active else DesignTokens.FG_2
		var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
		draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 6),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, ink)

func _draw_body() -> void:
	var pool: Array = Cards.UNLOCK_POOLS.get(_selected_hero, [])
	var locked_ids: Array = []
	var unlocked_ids: Array = []
	for cid in pool:
		if SaveSystem.is_card_unlocked(cid):
			unlocked_ids.append(cid)
		else:
			locked_ids.append(cid)
	# Two columns side by side. Left column: card unlocks. Right column: deck
	# swaps. If a section is empty it shows a quiet "Nothing yet" placeholder
	# so the layout doesn't collapse and the player still sees the heading.
	var col_w := (size.x - 96.0 - 48.0) * 0.5  # 48px gutter, 24px outer pad x2
	var left_x := 48.0
	var right_x := left_x + col_w + 48.0
	_draw_section(Vector2(left_x, BODY_TOP), col_w,
		"CARD UNLOCKS",
		"Spend tokens to add cards to your pool.",
		locked_ids, "unlock")
	_draw_section(Vector2(right_x, BODY_TOP), col_w,
		"DECK SWAPS",
		"Toggle which unlocked cards swap into your deck for next run.",
		unlocked_ids, "toggle_swap")

func _draw_section(origin: Vector2, col_w: float,
		eyebrow: String, sub: String,
		card_ids: Array, action_kind: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, origin + Vector2(0, DesignTokens.FS_XS),
		eyebrow, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	draw_string(font, origin + Vector2(0, DesignTokens.FS_XS + 22),
		sub, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_2)
	var rows_top := origin.y + 56.0
	if card_ids.is_empty():
		var empty := "Nothing here yet."
		draw_string(font, Vector2(origin.x, rows_top + 32),
			empty, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_MD, DesignTokens.NIGHT_4)
		return
	for i in card_ids.size():
		var cid: String = card_ids[i]
		var row_rect := Rect2(origin.x, rows_top + float(i) * (ROW_H + ROW_GAP), col_w, ROW_H)
		_draw_card_row(row_rect, cid, action_kind)

func _draw_card_row(rect: Rect2, card_id: String, action_kind: String) -> void:
	var font := ThemeDB.fallback_font
	var card: Dictionary = Cards.get_card(card_id)
	if card.is_empty():
		return
	var faction: String = String(card.get("faction", _selected_hero))
	var floor_color := DesignTokens.floor_color(faction)
	var core := DesignTokens.core_color(faction)
	# Row body — parchment fill, faction outline.
	draw_rect(rect, DesignTokens.PARCHMENT_0, true)
	draw_rect(rect, core, false, 1.0)
	# Faction stripe on the left edge.
	var stripe_w := 6.0
	draw_rect(Rect2(rect.position, Vector2(stripe_w, rect.size.y)), floor_color, true)
	# Body text.
	var text_x := rect.position.x + 18.0
	var name_y := rect.position.y + 24.0
	draw_string(font, Vector2(text_x, name_y),
		String(card.name), HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_LG, DesignTokens.PARCHMENT_INK)
	# Cost tag — coin-tinted, sits to the right of the name. Only shown if
	# the card has an in-run coin cost (resource cards are 0).
	var cost := int(card.cost)
	if cost > 0:
		var cost_label := "%d coin" % cost
		var cost_w := font.get_string_size(cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM).x
		draw_string(font, Vector2(rect.position.x + rect.size.x - ACTION_W - cost_w - 32, name_y),
			cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.NIGHT_3)
	# Description.
	draw_string(font, Vector2(text_x, name_y + 26),
		String(card.description), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - ACTION_W - 32, DesignTokens.FS_SM, DesignTokens.NIGHT_2)
	# Action button on the right.
	var action_rect := Rect2(
		rect.position.x + rect.size.x - ACTION_W - 12,
		rect.position.y + (rect.size.y - ACTION_H) * 0.5,
		ACTION_W, ACTION_H,
	)
	_draw_action_button(action_rect, card_id, action_kind, core)
	_row_actions.append({"rect": action_rect, "kind": action_kind, "card_id": card_id})

func _draw_action_button(rect: Rect2, card_id: String, kind: String, accent: Color) -> void:
	var font := ThemeDB.fallback_font
	var label := ""
	var enabled := true
	var label_color: Color = DesignTokens.FG_1
	match kind:
		"unlock":
			label = "Unlock · %d" % SaveSystem.UNLOCK_COST
			enabled = SaveSystem.can_afford_unlock()
			if not enabled:
				label_color = DesignTokens.FG_3
		"toggle_swap":
			if SaveSystem.is_card_in_deck(_selected_hero, card_id):
				label = "In deck — remove"
			else:
				label = "Add to deck"
	var fill: Color = DesignTokens.NIGHT_2 if enabled else DesignTokens.NIGHT_1
	draw_rect(rect, fill, true)
	draw_rect(rect, accent if enabled else DesignTokens.NIGHT_3, false, 2.0)
	# Centered label. The button is wide enough that wrapping isn't a concern
	# for the v0 copy lengths.
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x
	draw_string(font, rect.position + Vector2((rect.size.x - label_w) * 0.5, rect.size.y * 0.5 + 6),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD, label_color)

func _draw_close_button() -> void:
	var font := ThemeDB.fallback_font
	var w := CLOSE_W
	var h := CLOSE_H
	_close_rect = Rect2((size.x - w) * 0.5, size.y - h - 32, w, h)
	draw_rect(_close_rect, DesignTokens.NIGHT_2, true)
	draw_rect(_close_rect, DesignTokens.core_color(_selected_hero), false, 2.0)
	var label := "Done"
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG).x
	draw_string(font, _close_rect.position + Vector2((_close_rect.size.x - label_w) * 0.5, _close_rect.size.y * 0.5 + 8),
		label, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_LG, DesignTokens.FG_1)

func _draw_toast() -> void:
	if _toast == "":
		return
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_CENTER, -1, DesignTokens.FS_MD).x + 48.0
	var h := 40.0
	var rect := Rect2((size.x - w) * 0.5, size.y - h - 96, w, h)
	draw_rect(rect, DesignTokens.NIGHT_1, true)
	draw_rect(rect, DesignTokens.GOLD_COIN, false, 1.0)
	draw_string(font, rect.position + Vector2(24, rect.size.y * 0.5 + 6),
		_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_MD, DesignTokens.FG_1)

# ── helpers ───────────────────────────────────────────────────────────────

func _unlocked_count(hero_id: String) -> int:
	return SaveSystem.unlocked_pool_for(hero_id).size()
