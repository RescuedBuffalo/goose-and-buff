extends Control
##
## Run-end screen — victory or defeat in the survival rebuild. Carries
## a small "what happened" stat block: nights survived, resources
## gathered, enemies felled. The values are pushed by main.gd via
## set_stats() before show_*().

signal restart_requested()

@onready var _headline: Label = $Center/Panel/V/Headline
@onready var _sub: Label = $Center/Panel/V/Sub
@onready var _stats: Label = $Center/Panel/V/Stats
@onready var _button: Button = $Center/Panel/V/RestartButton

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _button != null:
		_button.pressed.connect(_on_restart_pressed)
	anchor_left = 0
	anchor_top = 0
	anchor_right = 1
	anchor_bottom = 1

func set_stats(nights_survived: int, resources_gathered: int, enemies_felled: int) -> void:
	if _stats == null:
		return
	# Sentence case + tabular numerals on counts. Voice rules apply to
	# every visible string in this widget.
	_stats.text = "Nights survived: %d  ·  resources gathered: %d  ·  enemies felled: %d" % [
		nights_survived, resources_gathered, enemies_felled,
	]

func show_victory() -> void:
	if _headline != null:
		_headline.text = "We held until spring."
	if _sub != null:
		_sub.text = "Three nights and the lodge still stands."
	visible = true

func show_defeat() -> void:
	if _headline != null:
		_headline.text = "The line broke."
	if _sub != null:
		_sub.text = "The lodge falls quiet."
	visible = true

func _on_restart_pressed() -> void:
	restart_requested.emit()
