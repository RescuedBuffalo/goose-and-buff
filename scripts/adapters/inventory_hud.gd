extends Control
##
## Inventory HUD adapter — bottom-of-screen 8-slot grid + equipped slot.
## Subscribes to InventorySystem signals and re-renders. Click a slot to
## select; right-click to clear selection. 1..8 hotkeys are wired in main
## (they call inventory.select_slot(idx-1) directly).
##
## Renders with design tokens — every color, font size, and spacing
## value comes from DesignTokens.

const Items := preload("res://data/items.gd")
const Placeables := preload("res://data/placeables.gd")

const SLOT_SIZE := Vector2(80, 80)
const SLOT_GAP := 8.0
# The HUD reserves a band at the bottom of the viewport for the grid;
# main.gd anchors this control to fill that band.
const BAND_HEIGHT := 120.0

var inventory: InventorySystem = null
var _slot_rects: Array = []  # rect per slot, in local control coords
var _equipped_rect: Rect2 = Rect2()
var _selected_index: int = 0

func bind(inventory_logic: InventorySystem) -> void:
	inventory = inventory_logic
	inventory.slot_changed.connect(func(_i, _s): queue_redraw())
	inventory.selected_changed.connect(_on_selected_changed)
	inventory.equipped_changed.connect(func(_w): queue_redraw())
	inventory.inventory_changed.connect(func(): queue_redraw())
	_selected_index = inventory.selected_index
	queue_redraw()

func _ready() -> void:
	# STOP — clicks anywhere on the bottom band are consumed by the
	# inventory, never falling through to combat / build below. The HUD
	# widget at the top uses IGNORE because it's purely informational.
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, BAND_HEIGHT)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if inventory == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		inventory.clear_selection()
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in _slot_rects.size():
		if (_slot_rects[i] as Rect2).has_point(mb.position):
			inventory.select_slot(i)
			accept_event()
			return

func _on_selected_changed(idx: int) -> void:
	_selected_index = idx
	queue_redraw()

func _draw() -> void:
	if inventory == null:
		return
	# Background band.
	var bg := Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.78)
	draw_rect(Rect2(0, 0, size.x, size.y), bg, true)
	draw_line(Vector2(0, 0), Vector2(size.x, 0), DesignTokens.DIVIDER, 2.0)
	# Layout: equipped slot on the right, 8 inventory slots centered.
	var total_w: float = (SLOT_SIZE.x * InventorySystem.SLOT_COUNT) + (SLOT_GAP * (InventorySystem.SLOT_COUNT - 1))
	var equipped_w: float = SLOT_SIZE.x + SLOT_GAP * 4.0
	var origin_x: float = (size.x - total_w - equipped_w) * 0.5
	var origin_y: float = (size.y - SLOT_SIZE.y) * 0.5
	_slot_rects = []
	for i in InventorySystem.SLOT_COUNT:
		var r := Rect2(
			Vector2(origin_x + i * (SLOT_SIZE.x + SLOT_GAP), origin_y),
			SLOT_SIZE,
		)
		_slot_rects.append(r)
		_draw_slot(r, inventory.slots[i], i == _selected_index, str(i + 1))
	# Equipped slot — shows the equipped weapon as a fixed display.
	var eq_x: float = origin_x + total_w + SLOT_GAP * 4.0
	_equipped_rect = Rect2(Vector2(eq_x, origin_y), SLOT_SIZE)
	_draw_equipped(_equipped_rect, inventory.equipped_weapon_id)

func _draw_slot(rect: Rect2, slot: Dictionary, is_selected: bool, hotkey: String) -> void:
	var bg := Color(DesignTokens.NIGHT_2.r, DesignTokens.NIGHT_2.g, DesignTokens.NIGHT_2.b, 0.92)
	draw_rect(rect, bg, true)
	var border_color: Color = DesignTokens.PARCHMENT_2 if is_selected else DesignTokens.NIGHT_4
	var border_w: float = 3.0 if is_selected else 1.0
	draw_rect(rect, border_color, false, border_w)
	# Hotkey badge — small numeral in the corner.
	var font: Font = ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(6, 18), hotkey,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	if slot.item_id.is_empty():
		return
	# Swatch as the placeholder "icon".
	var item: Dictionary = Items.get_item(slot.item_id)
	var swatch: Color = item.get("swatch", DesignTokens.FG_2)
	var swatch_rect := Rect2(rect.position + Vector2(16, 14), Vector2(rect.size.x - 32, rect.size.y - 36))
	draw_rect(swatch_rect, swatch, true)
	draw_rect(swatch_rect, DesignTokens.NIGHT_0, false, 1.5)
	# Stack count, bottom-right tabular numeral.
	var count_text: String = str(int(slot.count))
	var count_size: Vector2 = font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM)
	draw_string(font,
		rect.position + Vector2(rect.size.x - count_size.x - 6, rect.size.y - 6),
		count_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1,
		DesignTokens.FS_SM, DesignTokens.PARCHMENT_0,
	)

func _draw_equipped(rect: Rect2, weapon_id: String) -> void:
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.95)
	draw_rect(rect, bg, true)
	draw_rect(rect, DesignTokens.core_color(GameState.hero_id), false, 2.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(8, 18), "EQUIPPED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	# Match equipped_weapon_id to its item swatch via items table.
	var item_id: String = ""
	for id in Items.ALL:
		var item: Dictionary = Items.ALL[id]
		if item.get("weapon_id", "") == weapon_id:
			item_id = id
			break
	var swatch: Color = DesignTokens.FG_2
	var label: String = "Bare hands"
	if not item_id.is_empty():
		var item: Dictionary = Items.get_item(item_id)
		swatch = item.get("swatch", DesignTokens.FG_2)
		label = item.get("display_name", weapon_id)
	var swatch_rect := Rect2(rect.position + Vector2(16, 28), Vector2(rect.size.x - 32, rect.size.y - 50))
	draw_rect(swatch_rect, swatch, true)
	draw_rect(swatch_rect, DesignTokens.NIGHT_0, false, 1.5)
	# Name underneath.
	draw_string(font, rect.position + Vector2(8, rect.size.y - 6), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.PARCHMENT_0)
