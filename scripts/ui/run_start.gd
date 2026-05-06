extends Control
##
## Run-start screen (BUF-145). Hero selector + optional seed input.
## When the player picks a hero and clicks "Start the watch", the
## scene swaps to main.tscn after stamping the hero + seed onto the
## GameState autoload so main.gd's _ready can read them.
##
## Voice rules: sentence case, no emoji, totem names, "watch seed"
## rather than "seed" so it lands as game-fiction.
##
## BUF-129: hero variants are silently rolled here. Each hero with no
## current variant gets one assigned on _ready (so the swatch on the
## button shows *something*); on Start, the picked hero re-rolls so
## successive runs vary. No "you got the rust hide" pop — the variant
## is purely a swatch on the button + a sprite tint in-run, per the
## "no UI announcement" rule.

const WorldGenerator := preload("res://scripts/logic/world_generator.gd")
const HeroVariants := preload("res://data/hero_variants.gd")

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const LOBBY_SCENE_PATH := "res://scenes/ui/lobby.tscn"

# Diameter of the variant accent swatch drawn next to the hero name.
const VARIANT_SWATCH_DIAMETER := 18.0

@onready var _buffalo: Button = $Margin/V/HeroRow/Buffalo
@onready var _goose: Button = $Margin/V/HeroRow/Goose
@onready var _fox: Button = $Margin/V/HeroRow/Fox
@onready var _seed_input: LineEdit = $Margin/V/SeedRow/SeedInput
@onready var _start: Button = $Margin/V/Footer/StartButton
@onready var _multiplayer_button: Button = $Margin/V/Footer/MultiplayerButton

var _selected_hero: String = ""

func _ready() -> void:
	_buffalo.pressed.connect(_on_pick.bind("Buffalo"))
	_goose.pressed.connect(_on_pick.bind("Goose"))
	_fox.pressed.connect(_on_pick.bind("Fox"))
	_start.pressed.connect(_on_start)
	if _multiplayer_button != null:
		_multiplayer_button.pressed.connect(_on_multiplayer)
	# Solo entry point should leave any prior multiplayer session behind
	# so the M2 single-player game runs unchanged. A dev who clicked
	# Host, then Back, then Solo would otherwise still have a MpIo peer.
	if MpIo.is_multiplayer():
		MpIo.leave()
	# BUF-129: ensure each hero has a variant assigned so the buttons can
	# render their accent swatch. ensure_variant only rolls when missing —
	# already-rolled heroes keep their look until a run resets them.
	for hero_id in ["Buffalo", "Goose", "Fox"]:
		SaveIo.ensure_variant(hero_id)
	_attach_variant_swatches()
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
	# BUF-129: roll a fresh variant for the picked hero now — this is the
	# "new campaign begins" moment. Successive runs of the same hero
	# silently rotate looks. Other heroes' variants are left alone so the
	# select-screen swatches stay stable across un-picked totems.
	SaveIo.assign_variant_for_run(_selected_hero)
	var seed_text: String = _seed_input.text
	var seed_int: int = WorldGenerator.string_to_seed(seed_text)
	if seed_int == 0:
		seed_int = WorldGenerator.random_seed()
	GameState.set_hero(_selected_hero)
	GameState.set_run_config(seed_int, _selected_hero)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _on_multiplayer() -> void:
	# Lobby owns the multiplayer entry — this button just hands off.
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

# ── BUF-129: variant swatches ───────────────────────────────────────────

func _attach_variant_swatches() -> void:
	# A small disc in each hero button's top-right corner. The accent
	# color comes from the variant data, so the button reflects this
	# campaign's look without saying anything about it. Players notice
	# different swatches across runs — that's the design intent.
	_attach_swatch_to(_buffalo, "Buffalo")
	_attach_swatch_to(_goose, "Goose")
	_attach_swatch_to(_fox, "Fox")

func _attach_swatch_to(button: Button, hero_id: String) -> void:
	if button == null:
		return
	# Replace any pre-existing swatch from a previous _ready (defensive —
	# this scene is a one-shot in practice, but cheap to guard).
	var existing: Node = button.get_node_or_null("VariantSwatch")
	if existing != null:
		existing.queue_free()
	var variant_id: String = SaveIo.current_variant(hero_id)
	if variant_id.is_empty():
		return
	var swatch := _Swatch.new()
	swatch.name = "VariantSwatch"
	swatch.color = HeroVariants.accent_for(variant_id)
	swatch.diameter = VARIANT_SWATCH_DIAMETER
	swatch.size = Vector2(VARIANT_SWATCH_DIAMETER, VARIANT_SWATCH_DIAMETER)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to the button's top-right corner.
	swatch.anchor_left = 1.0
	swatch.anchor_right = 1.0
	swatch.anchor_top = 0.0
	swatch.anchor_bottom = 0.0
	swatch.offset_left = -VARIANT_SWATCH_DIAMETER - 12.0
	swatch.offset_top = 12.0
	swatch.offset_right = -12.0
	swatch.offset_bottom = 12.0 + VARIANT_SWATCH_DIAMETER
	button.add_child(swatch)

# Inner control draws a filled disc with a subtle outline so the swatch
# reads against any of the parchment / button background colors.
class _Swatch extends Control:
	var color: Color = Color(1, 1, 1, 1)
	var diameter: float = 18.0

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = diameter * 0.5
		# Outline first so the fill sits on top.
		draw_circle(center, radius + 1.0, Color(0, 0, 0, 0.30))
		draw_circle(center, radius, color)
