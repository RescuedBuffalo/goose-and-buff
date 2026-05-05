extends Control
##
## Run-end screen — victory or defeat. Single-button restart.
##
## Phase 1 keeps it minimal: a centered card with the headline + sub-line +
## a Try again button. M3 polish lands the lodge return / change-hero flow.

signal restart_requested()

@onready var _headline: Label = $Center/Panel/V/Headline
@onready var _sub: Label = $Center/Panel/V/Sub
@onready var _button: Button = $Center/Panel/V/RestartButton

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _button != null:
		_button.pressed.connect(_on_restart_pressed)
	# Fill the viewport so the scrim covers everything below.
	anchor_left = 0
	anchor_top = 0
	anchor_right = 1
	anchor_bottom = 1

func show_victory() -> void:
	if _headline != null:
		_headline.text = "Run complete."
	if _sub != null:
		_sub.text = "We held."
	visible = true

func show_defeat() -> void:
	if _headline != null:
		_headline.text = "Run ended."
	if _sub != null:
		_sub.text = "The line broke."
	visible = true

func _on_restart_pressed() -> void:
	restart_requested.emit()
