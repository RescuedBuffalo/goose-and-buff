extends Node2D
##
## Boot script. Builds logic modules, instantiates scene-tree adapters,
## wires signals between them. The only place where the layers meet.
##
## The split mirrors the Roblox project: pure GDScript modules carry
## state and emit signals; adapters subscribe and translate to scene
## changes. The wiring stays in this single file.

const Cards := preload("res://data/cards.gd")
const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Economy := preload("res://scripts/logic/economy.gd")
const CardSystem := preload("res://scripts/logic/card_system.gd")
const WaveDirector := preload("res://scripts/logic/wave_director.gd")
const AbilityResolver := preload("res://scripts/logic/ability_resolver.gd")

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const UnitScene := preload("res://scenes/unit.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BuildingScene := preload("res://scenes/building.tscn")
const HandScene := preload("res://scenes/ui/hand.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")

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
var building_node: Node = null  # at most one in v0

func _ready() -> void:
	randomize()
	_build_logic()
	_build_world()
	_build_ui()
	_wire_signals()
	_start_run()

func _build_logic() -> void:
	economy = Economy.new()
	card_system = CardSystem.new()
	wave_director = WaveDirector.new()

func _build_world() -> void:
	sector = SectorScene.instantiate()
	add_child(sector)
	hero = HeroScene.instantiate()
	add_child(hero)

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

func _start_run() -> void:
	GameState.reset()
	economy.reset()
	card_system.reset()
	wave_director.reset()
	card_system.start_round()
	GameState.set_phase(GameState.Phase.PREP)

func _process(delta: float) -> void:
	# Drive logic ticks. WaveDirector + Economy progress only here.
	wave_director.tick(delta)
	if wave_director.is_prep_phase() or wave_director.is_wave_phase():
		economy.tick(delta)
	if Input.is_action_just_pressed("ready_round") and wave_director.is_prep_phase():
		wave_director.ready_round()

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
	add_child(u)

func _place_or_upgrade_building(world_pos: Vector2) -> void:
	if building_node != null and is_instance_valid(building_node):
		var tier := economy.place_or_upgrade_node()
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
	var t = clamp((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var nearest := a + ab * t
	return p.distance_to(nearest) <= radius

func _show_charge_line(from: Vector2, to: Vector2, width: float) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = width
	line.default_color = Color(DesignTokens.BUFFALO_CORE.r, DesignTokens.BUFFALO_CORE.g, DesignTokens.BUFFALO_CORE.b, 0.55)
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

func _on_wave_ended(_round_index: int, _victory: bool) -> void:
	GameState.set_phase(GameState.Phase.DEBRIEF)
	# Sweep any survivors so the debrief is clean.
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()

func _on_core_destroyed() -> void:
	wave_director.note_core_destroyed()

func _on_run_complete() -> void:
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.show_victory()

func _on_run_ended() -> void:
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.show_defeat()

func _on_restart_requested() -> void:
	# Clear units, enemies, building, then restart the run cleanly.
	for n in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n): n.queue_free()
	if building_node != null and is_instance_valid(building_node):
		building_node.queue_free()
		building_node = null
	end_screen.visible = false
	sector.reset_core()
	# Reset hero hp.
	hero.hp = hero.hp_max
	GameState.set_hero_hp(hero.hp, hero.hp_max)
	_start_run()
