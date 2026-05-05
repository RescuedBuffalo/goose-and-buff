extends Node2D
##
## Boot script for the tile prototype. Builds logic modules, instantiates
## scene-tree adapters, and wires signals between them. Mirrors the role
## of godot-prototype/scripts/adapters/main.gd; the difference is that
## entity placement and card drop targeting work in tile coords now.
##
## The pure logic + data layers port verbatim from the top-down prototype.
## Anything tile-aware lives here or in scripts/adapters/sector.gd.

const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Cards := preload("res://data/cards.gd")

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const UnitScene := preload("res://scenes/unit.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BuildingScene := preload("res://scenes/building.tscn")
const HandScene := preload("res://scenes/ui/hand.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")

# Logic modules. Constructed once per run, reset between runs.
var economy
var card_system
var wave_director

# Adapter / scene refs.
var sector
var hero
var hand
var hud
var end_screen
var building_node: Node = null

# Aim line shown while an ability card is being dragged.
var _aim_line: Line2D = null
var _aim_target: Vector2 = Vector2.ZERO
var _aim_card_id: String = ""

# Signature ability cooldown — same model as godot-prototype.
var _signature_cd_remaining: float = 0.0
var _signature_cd_max: float = 0.0

# Phase 1 ships Buffalo only. Hero swap (Goose / Fox) lives in the original
# prototype; tile-rebuild adds it back once parity is locked.
const DEFAULT_HERO_ID := "Buffalo"

# Formation slot offsets — tile-space. The first unit dropped sits at
# (-1, +1) from the leader, second at (-1, -1), etc. Pre-defined so units
# don't pile onto the leader's tile.
const FORMATION_SLOTS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
	Vector2i(-2, 0),
	Vector2i(-2, 1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
	Vector2i(-3, 1),
	Vector2i(-3, -1),
]
var _next_slot_index: int = 0

func _ready() -> void:
	randomize()
	GameState.set_hero(DEFAULT_HERO_ID)
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
	hero.set_hero(DEFAULT_HERO_ID)
	hero.attach_sector(sector)
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
	hand.bind(card_system, economy)
	hand.play_requested.connect(_on_play_requested)
	hand.drag_started.connect(_on_drag_started)
	hand.drag_moved.connect(_on_drag_moved)
	hand.drag_ended.connect(_on_drag_ended)
	card_system.card_played.connect(_on_card_played)
	wave_director.enemy_due.connect(_on_enemy_due)
	wave_director.run_complete.connect(_on_run_complete)
	wave_director.run_ended.connect(_on_run_ended)
	wave_director.round_started.connect(_on_round_started)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	sector.core_destroyed.connect(_on_core_destroyed)
	end_screen.restart_requested.connect(_on_restart_requested)
	hero.hero_downed.connect(_on_hero_downed)

func _start_run() -> void:
	GameState.reset()
	GameState.set_hero(DEFAULT_HERO_ID)
	sector.set_hero(DEFAULT_HERO_ID)
	sector.reset_core()
	hero.reset_hp()
	hero.reset_position()
	economy.reset()
	card_system.reset(GameState.hero_id)
	wave_director.reset()
	_next_slot_index = 0
	GameState.set_phase(GameState.Phase.PREP)
	_reset_signature_cooldown()
	end_screen.visible = false
	hud.visible = true
	hand.visible = true

func _process(delta: float) -> void:
	wave_director.tick(delta)
	if wave_director.is_prep_phase() or wave_director.is_wave_phase():
		economy.tick(delta)
	if Input.is_action_just_pressed("ready_round") and wave_director.is_prep_phase():
		wave_director.ready_round()
	GameState.set_retreat(Input.is_action_pressed("toggle_retreat"))
	_tick_signature_cooldown(delta)
	if Input.is_action_just_pressed("cast_signature"):
		_try_cast_signature()
	if _aim_line != null:
		_update_aim_line()

# ── Click-to-move (hero) ─────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Hand owns its own click handling for drag-pickup; we only listen for
	# clicks that fall through to the world layer (Control.MOUSE_FILTER_PASS
	# on the hand only consumes events on its rectangle).
	if hero == null or not is_instance_valid(hero):
		return
	if wave_director == null:
		return
	# Get the world-space mouse position once and route to the hero's tile
	# pathfinder via the sector.
	var world_pos: Vector2 = get_global_mouse_position()
	var tile: Vector2i = sector.world_to_tile(world_pos)
	if not Sectors.is_tile_in_grid(tile):
		return
	hero.walk_to(tile)

# ── Card play ────────────────────────────────────────────────────────────
func _on_play_requested(card_id: String, world_pos: Vector2) -> void:
	card_system.play_card_at(card_id, world_pos, _current_phase_name(), economy.balance)

func _on_drag_started(card_id: String, world_pos: Vector2) -> void:
	var card: Dictionary = Cards.get_card(card_id)
	if card.is_empty():
		return
	match card.kind:
		"unit", "building", "resource":
			sector.set_deploy_highlight(true)
		"ability":
			_aim_card_id = card_id
			_aim_target = world_pos
			_spawn_aim_line()

func _on_drag_moved(_card_id: String, world_pos: Vector2) -> void:
	_aim_target = world_pos
	_update_aim_line()

func _on_drag_ended() -> void:
	sector.set_deploy_highlight(false)
	_clear_aim_line()

func _spawn_aim_line() -> void:
	_clear_aim_line()
	if hero == null or not is_instance_valid(hero):
		return
	_aim_line = Line2D.new()
	_aim_line.width = 6.0
	var accent := DesignTokens.core_color(GameState.hero_id)
	_aim_line.default_color = Color(accent.r, accent.g, accent.b, 0.55)
	_aim_line.z_index = 4
	add_child(_aim_line)
	_update_aim_line()

func _update_aim_line() -> void:
	if _aim_line == null or hero == null or not is_instance_valid(hero):
		return
	# Snap the endpoint to the nearest in-grid tile center so the aim line
	# reads as "casting toward THIS tile" rather than a free-floating point.
	var target_tile: Vector2i = sector.clamp_tile(sector.world_to_tile(_aim_target))
	var endpoint := sector.tile_to_world(target_tile)
	_aim_line.clear_points()
	_aim_line.add_point(hero.position)
	_aim_line.add_point(endpoint)

func _clear_aim_line() -> void:
	_aim_card_id = ""
	if _aim_line != null and is_instance_valid(_aim_line):
		_aim_line.queue_free()
	_aim_line = null

func _current_phase_name() -> String:
	if wave_director.is_prep_phase():
		return "prep"
	if wave_director.is_wave_phase():
		return "wave"
	return "other"

func _on_card_played(card: Dictionary, world_pos: Vector2) -> void:
	# Building cards no-op when at max tier — don't charge for a no-op play.
	if card.kind == "building" and economy.production_tier >= Economy.PRODUCTION_TIERS.size():
		return
	if int(card.cost) > 0:
		economy.spend(int(card.cost))
	# Convert the drop point to a tile. World pos comes from the hand widget;
	# clamping keeps drops near the edge of the grid still legal.
	var target_tile: Vector2i = sector.clamp_tile(sector.world_to_tile(world_pos))
	match card.kind:
		"unit":
			_spawn_unit(card.payload.unit_id, target_tile)
		"building":
			_place_or_upgrade_building(target_tile)
		"resource":
			economy.add(int(card.payload.coin_delta))
		"ability":
			_resolve_ability(card.payload.ability_id, sector.tile_to_world(target_tile))

func _spawn_unit(unit_id: String, drop_tile: Vector2i) -> void:
	# If the dropped tile is walkable use it; otherwise fall back to a slot
	# behind the leader. Avoids lossy "wasted card" UX when the player drops
	# on the core tile.
	var spawn_tile: Vector2i = drop_tile
	if not sector.is_tile_walkable(spawn_tile):
		spawn_tile = _next_formation_tile()
	var u: Node2D = UnitScene.instantiate()
	u.configure(unit_id)
	u.attach_sector(sector)
	# Formation offset is the slot the unit should drift toward when idle —
	# walks back to it when no enemy is in the detection bubble.
	var offset: Vector2i = FORMATION_SLOTS[_next_slot_index % FORMATION_SLOTS.size()]
	_next_slot_index += 1
	u.bind_leader(hero, offset)
	add_child(u)
	u.place_at_tile(spawn_tile)

func _next_formation_tile() -> Vector2i:
	var offset: Vector2i = FORMATION_SLOTS[_next_slot_index % FORMATION_SLOTS.size()]
	return sector.clamp_tile(hero.current_tile + offset)

func _place_or_upgrade_building(drop_tile: Vector2i) -> void:
	if building_node != null and is_instance_valid(building_node):
		var tier: int = economy.place_or_upgrade_node()
		building_node.set_tier(tier)
		return
	# Snap to the drop tile, but bump off the spawn / core tiles if the
	# player happened to drop on top of either.
	var target_tile: Vector2i = drop_tile
	if target_tile == Sectors.SPAWN_TILE or target_tile == Sectors.CORE_TILE \
			or not sector.is_tile_walkable(target_tile):
		target_tile = Sectors.PRODUCTION_NODE_DEFAULT_TILE
	economy.place_or_upgrade_node()
	var b: Node2D = BuildingScene.instantiate()
	add_child(b)
	b.place_at_tile(target_tile, sector)
	building_node = b

# ── Signature ability ────────────────────────────────────────────────────
func _try_cast_signature() -> void:
	if not wave_director.is_wave_phase():
		return
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	if _signature_cd_remaining > 0.0:
		return
	var hero_def: Dictionary = Heroes.ALL.get(GameState.hero_id, Heroes.Buffalo)
	var ability_id: String = hero_def.get("signatureAbilityId", "")
	if ability_id.is_empty():
		return
	var mouse_world := get_global_mouse_position()
	var target_tile: Vector2i = sector.clamp_tile(sector.world_to_tile(mouse_world))
	var target_world: Vector2 = sector.tile_to_world(target_tile)
	_resolve_ability(ability_id, target_world)
	var cooldown: float = float(hero_def.get("signatureCooldown", 5.0))
	_signature_cd_max = cooldown
	_signature_cd_remaining = cooldown
	GameState.set_signature_cooldown(_signature_cd_remaining, _signature_cd_max)

func _tick_signature_cooldown(delta: float) -> void:
	if _signature_cd_remaining <= 0.0:
		return
	_signature_cd_remaining = max(0.0, _signature_cd_remaining - delta)
	GameState.set_signature_cooldown(_signature_cd_remaining, _signature_cd_max)

func _reset_signature_cooldown() -> void:
	_signature_cd_remaining = 0.0
	_signature_cd_max = 0.0
	GameState.set_signature_cooldown(0.0, 0.0)

# ── Ability resolution ───────────────────────────────────────────────────
func _resolve_ability(ability_id: String, target_pos: Vector2) -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	var effects := AbilityResolver.resolve(ability_id, hero.position, target_pos)
	for fx in effects:
		match fx.kind:
			"damage_in_capsule":
				_apply_capsule_damage(fx)
				_show_charge_line(fx.from, fx.to, fx.width)
			"damage_in_cone":
				_apply_cone_damage(fx)
			"dash_and_strike":
				pass  # Phase 2 — Fox not in scope for parity rebuild

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

func _apply_cone_damage(fx: Dictionary) -> void:
	var apex: Vector2 = fx.from
	var dir: Vector2 = fx.direction
	var length: float = float(fx.length)
	var half_angle: float = float(fx.half_angle)
	var cos_threshold := cos(half_angle)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		var to_enemy := e.position - apex
		var dist := to_enemy.length()
		if dist <= 0.0001 or dist > length:
			continue
		if to_enemy.normalized().dot(dir) < cos_threshold:
			continue
		e.damage(float(fx.damage))
		if is_instance_valid(e):
			e.apply_knockback(dir, float(fx.knockback))

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

# ── Wave / round transitions ─────────────────────────────────────────────
func _on_enemy_due(enemy_type: String, slot_index: int) -> void:
	var entry_tiles: Array[Vector2i] = Sectors.ENEMY_ENTRY_TILES
	var entry_tile: Vector2i = entry_tiles[slot_index % entry_tiles.size()]
	var e: Node2D = EnemyScene.instantiate()
	e.configure(enemy_type)
	e.attach_sector(sector)
	e.died.connect(func(_n): wave_director.note_enemy_killed())
	e.reached_core.connect(_on_enemy_reached_core)
	add_child(e)
	e.place_at_tile(entry_tile)
	wave_director.note_enemy_spawned()

func _on_enemy_reached_core(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	sector.damage_core(float(enemy.data.damage))
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
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	_reset_signature_cooldown()
	if victory:
		_reset_to_base()

func _reset_to_base() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	hero.revive()
	hero.reset_position()
	# Snap units back to their formation slots adjacent to the hero — same
	# spirit as the original tween-back, only tile-grain.
	var slot_idx := 0
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		var offset: Vector2i = FORMATION_SLOTS[slot_idx % FORMATION_SLOTS.size()]
		slot_idx += 1
		u.place_at_tile(sector.clamp_tile(hero.current_tile + offset))

func _on_hero_downed() -> void:
	if hud != null and hud.has_method("show_banner"):
		hud.show_banner("Hero is down — hold the line!", 2.5)

func _on_core_destroyed() -> void:
	wave_director.note_core_destroyed()

func _on_run_complete() -> void:
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.show_victory()

func _on_run_ended() -> void:
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.show_defeat()

func _on_restart_requested() -> void:
	for n in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n): n.queue_free()
	if building_node != null and is_instance_valid(building_node):
		building_node.queue_free()
		building_node = null
	if sector != null and is_instance_valid(sector):
		sector.set_deploy_highlight(false)
	_clear_aim_line()
	_start_run()
