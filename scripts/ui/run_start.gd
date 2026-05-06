extends Control
##
## Run-start screen (BUF-145). Hero selector + optional seed input.
## When the player picks a hero and clicks "Start the watch", the
## scene swaps to main.tscn after stamping the hero + seed onto the
## GameState autoload so main.gd's _ready can read them.
##
## Voice rules: sentence case, no emoji, totem names, "watch seed"
## rather than "seed" so it lands as game-fiction.

const WorldGenerator := preload("res://scripts/logic/world_generator.gd")
const Heroes := preload("res://data/heroes.gd")

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

@onready var _buffalo: Button = $Margin/V/HeroRow/Buffalo
@onready var _goose: Button = $Margin/V/HeroRow/Goose
@onready var _fox: Button = $Margin/V/HeroRow/Fox
@onready var _seed_input: LineEdit = $Margin/V/SeedRow/SeedInput
@onready var _start: Button = $Margin/V/Footer/StartButton

var _selected_hero: String = ""

func _ready() -> void:
	_buffalo.pressed.connect(_on_pick.bind("Buffalo"))
	_goose.pressed.connect(_on_pick.bind("Goose"))
	_fox.pressed.connect(_on_pick.bind("Fox"))
	_start.pressed.connect(_on_start)
	_refresh_buttons()

func _on_pick(hero_id: String) -> void:
	_selected_hero = hero_id
	_refresh_buttons()

func _refresh_buttons() -> void:
	# Visual selection state — the picked totem stays "pressed" so the
	# player has a clear read of what's locked in. No emoji per voice
	# rules; the button text + a subtle border via toggle-mode does it.
	_buffalo.button_pressed = _selected_hero == "Buffalo"
	_goose.button_pressed = _selected_hero == "Goose"
	_fox.button_pressed = _selected_hero == "Fox"
	_buffalo.toggle_mode = true
	_goose.toggle_mode = true
	_fox.toggle_mode = true
	_start.disabled = _selected_hero.is_empty()

func _on_start() -> void:
	if _selected_hero.is_empty():
		return
	var seed_text: String = _seed_input.text
	var seed_int: int = WorldGenerator.string_to_seed(seed_text)
	if seed_int == 0:
		seed_int = WorldGenerator.random_seed()
	GameState.set_hero(_selected_hero)
	GameState.set_run_config(seed_int, _selected_hero)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
