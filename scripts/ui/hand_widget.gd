extends Control
##
## Renders the player's hand and translates drag-drop into "play card at"
## requests. Listens to a CardSystem instance via the `bind` method —
## the hand never reaches into the logic module's internals directly.

const CardScene := preload("res://scenes/ui/card.tscn")
const CardWidget := preload("res://scripts/ui/card_widget.gd")
const Sectors := preload("res://data/sectors.gd")

signal play_requested(card_id: String, position: Vector2)

const CARD_GAP := 16.0
const HAND_BOTTOM_PADDING := 24.0

var _card_system  # CardSystem
var _hand_ids: Array = []
var _drag_widget: Control = null
var _drag_card_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO

func bind(card_system) -> void:
	_card_system = card_system
	_card_system.hand_changed.connect(_on_hand_changed)
	_card_system.play_rejected.connect(_on_play_rejected)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchor_left = 0
	anchor_right = 1
	anchor_bottom = 1
	anchor_top = 1
	offset_top = -240
	offset_left = 0
	offset_right = 0
	offset_bottom = 0

func _on_hand_changed(hand: Array) -> void:
	_hand_ids = hand.duplicate()
	# Defer one frame so layout has computed our size before card placement.
	_rebuild.call_deferred()

func _on_play_rejected(_card_id: String, _reason: String) -> void:
	# Card stays in hand logically — snap the dragged widget back to its
	# slot so the visual matches the model.
	_rebuild.call_deferred()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if _hand_ids.is_empty():
		return
	# Explicit float typing — max() on ints would otherwise leave total_w
	# untyped, which Godot's static checker rejects.
	var card_w: float = CardWidget.CARD_SIZE.x
	var gap_count: float = float(max(0, _hand_ids.size() - 1))
	var total_w: float = float(_hand_ids.size()) * card_w + gap_count * CARD_GAP
	var start_x: float = (size.x - total_w) * 0.5
	var y: float = size.y - CardWidget.CARD_SIZE.y - HAND_BOTTOM_PADDING
	for i in _hand_ids.size():
		var card_id: String = _hand_ids[i]
		var widget: Control = CardScene.instantiate()
		widget.position = Vector2(start_x + i * (card_w + CARD_GAP), y)
		widget.set_card(card_id)
		add_child(widget)

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
			return

func _try_drop(local_pos: Vector2) -> void:
	if _drag_widget == null:
		return
	# Convert local hand-coords to global viewport coords for the play target.
	var global_drop := global_position + local_pos
	# Every card kind requires the drop to land in the sector. For ability
	# cards the drop position becomes the cast target; for unit / building
	# cards it's the spawn point. Out-of-bounds drops snap back to the hand.
	if Sectors.is_inside_sector(global_drop):
		play_requested.emit(_drag_card_id, global_drop)
	else:
		_rebuild()
	_drag_widget = null
	_drag_card_id = ""
