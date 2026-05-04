extends Node2D
##
## Boot script. Builds logic modules, instantiates scene-tree adapters,
## wires signals between them. The only place where the layers meet.
##
## The split mirrors the Roblox project: pure GDScript modules carry
## state and emit signals; adapters subscribe and translate to scene
## changes. The wiring stays in this single file.

const Sectors := preload("res://data/sectors.gd")
# Logic classes (Economy, CardSystem, WaveDirector, AbilityResolver) and the
# data classes that have a class_name are reachable as globals — no need to
# alias them via const here.

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const UnitScene := preload("res://scenes/unit.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BuildingScene := preload("res://scenes/building.tscn")
const HandScene := preload("res://scenes/ui/hand.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")
const HeroSelectScene := preload("res://scenes/ui/hero_select.tscn")

# Logic
var economy
var card_system
var wave_director

# Adapters / scene refs
var sector
var hero
var hand
var hud
var end_screen
var hero_select
var building_node: Node = null  # at most one in v0
# Hero is rebuilt fresh each run so a different pick can swap sprite +
# stats. Keeping it nullable lets _start_run handle both first launch
# (no hero yet) and post-restart (old hero already freed).
const DEFAULT_HERO_ID := "Buffalo"

func _ready() -> void:
	randomize()
	_build_logic()
	_build_world()
	_build_ui()
	_wire_signals()
	_open_hero_select()

func _build_logic() -> void:
	economy = Economy.new()
	card_system = CardSystem.new()
	wave_director = WaveDirector.new()

func _build_world() -> void:
	# The hero is intentionally NOT instanced here — _start_run instances it
	# fresh per pick so hero_data / sprite / spawn pad reflect the choice.
	sector = SectorScene.instantiate()
	add_child(sector)

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = HudScene.instantiate()
	ui_layer.add_child(hud)
	hand = HandScene.instantiate()
	ui_layer.add_child(hand)
	end_screen = EndScene.instantiate()
	ui_layer.add_child(end_screen)
	hero_select = HeroSelectScene.instantiate()
	ui_layer.add_child(hero_select)

func _wire_signals() -> void:
	hud.bind(economy, wave_director, sector)
	hand.bind(card_system)
	hand.play_requested.connect(_on_play_requested)
	card_system.card_played.connect(_on_card_played)
	wave_director.enemy_due.connect(_on_enemy_due)
	wave_director.run_complete.connect(_on_run_complete)
	wave_director.run_ended.connect(_on_run_ended)
	wave_director.round_started.connect(_on_round_started)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	sector.core_destroyed.connect(_on_core_destroyed)
	end_screen.restart_requested.connect(_on_restart_requested)
	end_screen.change_hero_requested.connect(_on_change_hero_requested)
	hero_select.hero_selected.connect(_on_hero_selected)

func _open_hero_select() -> void:
	# The select screen is the entry point. Hide the in-run UI so the
	# curtain pulls clean, and pause the wave clock so the 30s prep timer
	# doesn't tick while the player is still picking (see _process).
	GameState.set_phase(GameState.Phase.PREP)
	end_screen.visible = false
	hud.visible = false
	hand.visible = false
	hero_select.open()

func _on_hero_selected(hero_id: String) -> void:
	GameState.set_hero(hero_id)
	# Sector retones immediately so the curtain pull-back lands on the
	# correct palette.
	sector.set_hero(hero_id)
	_spawn_hero(hero_id)
	hud.visible = true
	hand.visible = true
	_start_run()

func _spawn_hero(hero_id: String) -> void:
	# Tear down any prior hero — happens on the "Change hero" path.
	if hero != null and is_instance_valid(hero):
		hero.queue_free()
	hero = HeroScene.instantiate()
	hero.set_hero(hero_id)
	add_child(hero)

func _start_run() -> void:
	GameState.reset()
	# Republish world-owned state into GameState — GameState.reset() zeroed
	# core/hero HP, and the sector/hero set their values during _ready, so
	# without this the HUD would show 0/0 until the first damage tick.
	sector.reset_core()
	hero.reset_hp()
	hero.reset_position()
	economy.reset()
	card_system.reset()
	wave_director.reset()
	card_system.start_round()
	GameState.set_phase(GameState.Phase.PREP)

func _process(delta: float) -> void:
	# Don't tick the run while the hero select is up — otherwise the prep
	# timer would burn down behind the curtain.
	if hero_select != null and hero_select.visible:
		return
	# Drive logic ticks. WaveDirector + Economy progress only here.
	wave_director.tick(delta)
	if wave_director.is_prep_phase() or wave_director.is_wave_phase():
		economy.tick(delta)
	if Input.is_action_just_pressed("ready_round") and wave_director.is_prep_phase():
		wave_director.ready_round()
	# Hold-to-retreat: while the key is down, units ignore enemies. The
	# setter short-circuits when the value is unchanged, so polling every
	# frame is fine.
	GameState.set_retreat(Input.is_action_pressed("toggle_retreat"))

func _on_play_requested(card_id: String, world_pos: Vector2) -> void:
	card_system.play_card_at(card_id, world_pos, _current_phase_name(), economy.balance)

func _current_phase_name() -> String:
	if wave_director.is_prep_phase():
		return "prep"
	if wave_director.is_wave_phase():
		return "wave"
	return "other"

func _on_card_played(card: Dictionary, world_pos: Vector2) -> void:
	# Pay cost first; the logic layer has already validated.
	if int(card.cost) > 0:
		economy.spend(int(card.cost))
	match card.kind:
		"unit":
			_spawn_unit(card.payload.unit_id, world_pos)
		"building":
			_place_or_upgrade_building(world_pos)
		"resource":
			economy.add(int(card.payload.coin_delta))
		"ability":
			_resolve_ability(card.payload.ability_id, world_pos)

func _spawn_unit(unit_id: String, world_pos: Vector2) -> void:
	var u: Node2D = UnitScene.instantiate()
	u.configure(unit_id)
	u.position = world_pos
	# Each unit picks a stable formation slot relative to the leader so a
	# growing army doesn't collapse onto a single point. Random offset is
	# fine for v0; a tighter ring layout can come later.
	var offset := _random_formation_offset()
	u.bind_leader(hero, offset)
	add_child(u)

func _random_formation_offset() -> Vector2:
	# Slot is biased behind/below the leader (negative x) so units flank
	# the spawn pad rather than crowd Buffalo's nose.
	var x := randf_range(-72.0, -16.0)
	var y := randf_range(-56.0, 56.0)
	return Vector2(x, y)

func _place_or_upgrade_building(world_pos: Vector2) -> void:
	if building_node != null and is_instance_valid(building_node):
		var tier: int = economy.place_or_upgrade_node()
		building_node.set_tier(tier)
		return
	economy.place_or_upgrade_node()
	var b: Node2D = BuildingScene.instantiate()
	b.position = world_pos
	add_child(b)
	building_node = b

func _resolve_ability(ability_id: String, target_pos: Vector2) -> void:
	var effects := AbilityResolver.resolve(ability_id, hero.position, target_pos)
	for fx in effects:
		match fx.kind:
			"damage_in_capsule":
				_apply_capsule_damage(fx)
				_show_charge_line(fx.from, fx.to, fx.width)

func _apply_capsule_damage(fx: Dictionary) -> void:
	var from: Vector2 = fx.from
	var to: Vector2 = fx.to
	var width: float = float(fx.width)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if _point_in_capsule(e.position, from, to, width * 0.5):
			e.damage(float(fx.damage))
			if is_instance_valid(e):
				e.apply_knockback(fx.direction, float(fx.knockback))

func _point_in_capsule(p: Vector2, a: Vector2, b: Vector2, radius: float) -> bool:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq <= 0.0001:
		return p.distance_to(a) <= radius
	var t: float = clamp((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var nearest: Vector2 = a + ab * t
	return p.distance_to(nearest) <= radius

func _show_charge_line(from: Vector2, to: Vector2, width: float) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = width
	var accent := DesignTokens.core_color(GameState.hero_id)
	line.default_color = Color(accent.r, accent.g, accent.b, 0.55)
	line.z_index = 5
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.45)
	tween.tween_callback(line.queue_free)

func _on_enemy_due(enemy_type: String, slot_index: int) -> void:
	var e: Node2D = EnemyScene.instantiate()
	e.configure(enemy_type)
	# Stagger Y across the sector band so enemies arrive in a spread.
	var band_top := Sectors.SECTOR_TOP + 64
	var band_bot := Sectors.SECTOR_BOTTOM - 64
	var y := band_top + (slot_index * 53) % int(band_bot - band_top)
	e.position = Vector2(Sectors.ENEMY_ENTRY_X, y)
	e.died.connect(func(_n): wave_director.note_enemy_killed())
	e.reached_core.connect(_on_enemy_reached_core)
	add_child(e)
	wave_director.note_enemy_spawned()

func _on_enemy_reached_core(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	sector.damage_core(float(enemy.data.damage))
	# After landing the hit, the enemy is consumed — they die into the core.
	wave_director.note_enemy_killed()
	enemy.queue_free()

func _on_round_started(_round_index: int) -> void:
	GameState.set_phase(GameState.Phase.PREP)
	GameState.round_index = _round_index
	card_system.start_round()

func _on_wave_started(_round_index: int, _composition: Dictionary) -> void:
	GameState.set_phase(GameState.Phase.WAVE)

func _on_wave_ended(_round_index: int, victory: bool) -> void:
	GameState.set_phase(GameState.Phase.DEBRIEF)
	# Sweep any survivors so the debrief is clean.
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	# A loss skips the reset — the run is ending, end screen takes over.
	if victory:
		_reset_to_base()

const RESET_DURATION := 0.6

func _reset_to_base() -> void:
	# Tween Buffalo and any surviving units back to the spawn pad area.
	# AI / input stays off on each entity for the duration of the tween.
	var hero_target: Vector2 = hero.spawn_position()
	_tween_back(hero, hero_target)
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		_tween_back(u, hero_target + u.formation_offset)

func _tween_back(node: Node2D, target: Vector2) -> void:
	# Helper extracted so each tween captures its own `node` by argument
	# rather than via a loop-variable closure.
	node.set_scripted_motion(true)
	var t := create_tween()
	t.tween_property(node, "position", target, RESET_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_release_scripted_motion.bind(node))

func _release_scripted_motion(node: Node) -> void:
	if is_instance_valid(node):
		node.set_scripted_motion(false)

func _on_core_destroyed() -> void:
	wave_director.note_core_destroyed()

func _on_run_complete() -> void:
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.show_victory()

func _on_run_ended() -> void:
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.show_defeat()

func _on_restart_requested() -> void:
	# "Try again" — same hero, fresh run. Clear transients; _start_run
	# re-publishes core/hero HP itself.
	_clear_run_transients()
	end_screen.visible = false
	_start_run()

func _on_change_hero_requested() -> void:
	# "Change hero" — back to hero select. Tear down hero too so the next
	# pick instantiates a fresh one with the right sprite + stats.
	_clear_run_transients()
	if hero != null and is_instance_valid(hero):
		hero.queue_free()
		hero = null
	end_screen.visible = false
	_open_hero_select()

func _clear_run_transients() -> void:
	for n in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n): n.queue_free()
	if building_node != null and is_instance_valid(building_node):
		building_node.queue_free()
		building_node = null
