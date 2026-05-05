extends Control
##
## Renders the player's hand and translates drag-drop into "play card at"
## requests. Listens to a CardSystem instance via the `bind` method.
##
## Drop targeting: the hand reports the drop in global viewport coords; the
## main adapter converts that to a tile via the sector. Drop-outside-grid
## snaps the card back to the hand.

const CardScene := preload("res://scenes/ui/card.tscn")
const CardWidget := preload("res://scripts/ui/card_widget.gd")
const Sectors := preload("res://data/sectors.gd")

signal play_requested(card_id: String, position: Vector2)
signal drag_started(card_id: String, world_pos: Vector2)
signal drag_moved(card_id: String, world_pos: Vector2)
signal drag_ended()

const CARD_GAP := 18.0
const HAND_BOTTOM_PADDING := 24.0
# Visual height of the card-bearing strip at the bottom. The hand Control
# itself spans the whole viewport (so drag-release outside the strip still
# fires _gui_input) but cards are laid out only inside this band.
const HAND_BAND_HEIGHT_PX := Sectors.HAND_BAND_HEIGHT

var _card_system  # CardSystem
var _economy
var _hand_ids: Array = []
var _drag_widget: Control = null
var _drag_card_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO

func bind(card_system, economy = null) -> void:
	_card_system = card_system
	_card_system.hand_changed.connect(_on_hand_changed)
	_card_system.play_rejected.connect(_on_play_rejected)
	if economy != null:
		_economy = economy
		_economy.balance_changed.connect(_on_balance_changed)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Span the whole viewport. Cards render in the bottom strip via
	# _band_y(); making the Control full-screen lets drag-release events
	# outside the strip still hit _gui_input — Godot Controls don't capture
	# the mouse, so a release outside the rect is silently dropped otherwise.
	anchor_left = 0
	anchor_right = 1
	anchor_top = 0
	anchor_bottom = 1
	offset_top = 0
	offset_left = 0
	offset_right = 0
	offset_bottom = 0
	queue_redraw()

func _on_hand_changed(hand: Array) -> void:
	_hand_ids = hand.duplicate()
	_rebuild.call_deferred()

func _on_play_rejected(_card_id: String, _reason: String) -> void:
	_rebuild.call_deferred()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if _hand_ids.is_empty():
		return
	var card_w: float = CardWidget.CARD_SIZE.x
	var gap_count: float = float(max(0, _hand_ids.size() - 1))
	var total_w: float = float(_hand_ids.size()) * card_w + gap_count * CARD_GAP
	var start_x: float = (size.x - total_w) * 0.5
	# Card row sits inside the bottom HAND_BAND_HEIGHT_PX of the viewport.
	var y: float = size.y - CardWidget.CARD_SIZE.y - HAND_BOTTOM_PADDING
	for i in _hand_ids.size():
		var card_id: String = _hand_ids[i]
		var widget: Control = CardScene.instantiate()
		widget.position = Vector2(start_x + i * (card_w + CARD_GAP), y)
		widget.set_card(card_id)
		add_child(widget)
	_apply_affordability()

func _band_top() -> float:
	# Top of the visible hand band relative to the Control's local rect.
	# Anything above this is "the world" for drop-targeting purposes.
	return size.y - HAND_BAND_HEIGHT_PX

func _on_balance_changed(_new_balance: int) -> void:
	_apply_affordability()

func _apply_affordability() -> void:
	if _economy == null:
		return
	var balance: int = _economy.balance
	for child in get_children():
		if child is CardWidget:
			var w: CardWidget = child
			if w.card.is_empty():
				continue
			w.set_affordable(int(w.card.cost) <= balance)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_try_pick_up(mb.position)
		else:
			_try_drop(mb.position)
	elif event is InputEventMouseMotion and _drag_widget != null:
		_drag_widget.position = event.position - _drag_offset
		drag_moved.emit(_drag_card_id, global_position + event.position)

func _try_pick_up(local_pos: Vector2) -> void:
	for child in get_children():
		if not (child is Control):
			continue
		var widget: Control = child
		var rect := Rect2(widget.position, widget.custom_minimum_size)
		if rect.has_point(local_pos):
			_drag_widget = widget
			_drag_card_id = widget.card_id
			_drag_offset = local_pos - widget.position
			move_child(widget, get_child_count() - 1)
			drag_started.emit(_drag_card_id, global_position + local_pos)
			# Stop the click from bubbling to the world layer (would
			# otherwise issue a click-to-move command on pickup).
			accept_event()
			return

func _try_drop(local_pos: Vector2) -> void:
	if _drag_widget == null:
		return
	var global_drop: Vector2 = global_position + local_pos
	# Drops above the hand band (sector / HUD area) are forwarded to main —
	# main converts to a tile and validates the play. Drops inside the band
	# snap the card back to the hand row.
	if local_pos.y < _band_top():
		play_requested.emit(_drag_card_id, global_drop)
	else:
		_rebuild()
	_drag_widget = null
	_drag_card_id = ""
	drag_ended.emit()
	accept_event()
