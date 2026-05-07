extends Control
##
## Run-end screen — victory or defeat in the survival rebuild. Carries
## a small "what happened" stat block: nights survived, resources
## gathered, enemies felled. The values are pushed by main.gd via
## set_stats() before show_*().
##
## M2 (BUF-145, BUF-149): displays the run's watch seed plus a Copy
## button, and the embers earned for sharing the run with the lodge
## tree UI.

const WorldGenerator := preload("res://scripts/logic/world_generator.gd")

signal restart_requested()
# Emitted when the player interacts with the end screen (Copy seed,
# Run again). main.gd listens and cancels the auto-transition timer
# so the screen sits open as long as the player wants. Without this,
# the 1.6s default closes the seed Copy button before anyone can hit it.
signal player_engaged()

@onready var _headline: Label = $Center/Panel/V/Headline
@onready var _sub: Label = $Center/Panel/V/Sub
@onready var _stats: Label = $Center/Panel/V/Stats
@onready var _embers_earned: Label = $Center/Panel/V/EmbersEarned
@onready var _seed_label: Label = $Center/Panel/V/SeedRow/SeedLabel
@onready var _copy_seed: Button = $Center/Panel/V/SeedRow/CopySeed
@onready var _button: Button = $Center/Panel/V/RestartButton

var _displayed_seed: int = 0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _button != null:
		_button.pressed.connect(_on_restart_pressed)
	if _copy_seed != null:
		_copy_seed.pressed.connect(_on_copy_seed_pressed)
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

func set_seed(seed_int: int) -> void:
	_displayed_seed = seed_int
	if _seed_label != null:
		_seed_label.text = "Watch seed " + WorldGenerator.seed_to_string(seed_int)

func set_embers_earned(amount: int) -> void:
	if _embers_earned == null:
		return
	if amount <= 0:
		_embers_earned.text = ""
		return
	# Sentence case + tabular plural. Phrases the reward as a souvenir
	# rather than a score.
	if amount == 1:
		_embers_earned.text = "1 ember earned for the lodge."
	else:
		_embers_earned.text = "%d embers earned for the lodge." % amount

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
	player_engaged.emit()
	restart_requested.emit()

func _on_copy_seed_pressed() -> void:
	# Cancel the lodge auto-transition before doing the copy. If the
	# player took the time to click Copy, they want to *read* the seed
	# back too — let them take that time without the screen sliding
	# out from under them.
	player_engaged.emit()
	if _displayed_seed == 0:
		return
	var seed_text: String = WorldGenerator.seed_to_string(_displayed_seed)
	DisplayServer.clipboard_set(seed_text)
	if _copy_seed != null:
		# BUF-145 voice: confirmation reads "Seed copied." so the player
		# sees the same wording the ticket prescribes (and matches the
		# rest of the run-end scrim's sentence-case voice).
		_copy_seed.text = "Seed copied."
