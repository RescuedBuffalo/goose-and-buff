extends Node2D
##
## Boot script for the survival rebuild. Builds logic modules, instantiates
## scene-tree adapters, seeds the hand-crafted starter world, and wires
## signals between them.
##
## The wave-defense build had main wire a card hand and a phase button;
## the survival rebuild swaps both for the day/night cycle (auto phases)
## plus an inventory bar + build overlay (replaces the card hand).
##
## Pure logic + data layers stay verbatim from their files. Only the
## adapter wiring lives here.

const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Items := preload("res://data/items.gd")
const Resources := preload("res://data/resources.gd")
const DayNight := preload("res://data/day_night.gd")
const DayNightCycleClass := preload("res://scripts/logic/day_night_cycle.gd")
const WaveDirectorGate := preload("res://scripts/adapters/wave_director_gate.gd")
const LightingAdapterScript := preload("res://scripts/adapters/lighting_adapter.gd")
const InventoryHudScript := preload("res://scripts/adapters/inventory_hud.gd")
const BuildOverlayScript := preload("res://scripts/adapters/build_overlay.gd")
const CombatVisualsScript := preload("res://scripts/adapters/combat_visuals.gd")
const TelemetryIoScript := preload("res://scripts/adapters/telemetry_io.gd")

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const ResourceNodeScene := preload("res://scenes/resource_node.tscn")
const PlaceableScene := preload("res://scenes/placeable.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")

# Logic modules. Constructed once per run, reset between runs.
var day_night = null
var wave_director: WaveDirector = null
var inventory: InventorySystem = null
var combat: CombatSystem = null
var gather: GatherSystem = null
var build_logic: BuildSystem = null
var wave_gate = null
var telemetry: Telemetry = null

# Adapter / scene refs.
var sector
var hero
var hud
var end_screen
var inventory_hud
var build_overlay
var combat_visuals
var lighting
var telemetry_io = null

# Run-end stat tally — pushed onto the end-screen on victory/defeat.
var _resources_gathered: int = 0
var _enemies_felled: int = 0
var _nights_survived: int = 0

const DEFAULT_HERO_ID := "Buffalo"

# Starter inventory — gives the player a hand axe and one wall stack so
# they can immediately do something on Day 1 without hunting for tools.
const STARTER_ITEMS: Array = [
	{"id": "hand_axe", "count": 1},
	{"id": "wood_wall", "count": 4},
]

func _ready() -> void:
	randomize()
	GameState.set_hero(DEFAULT_HERO_ID)
	_build_logic()
	_build_world()
	_build_ui()
	_wire_signals()
	_seed_world_resources()
	_start_run()

func _build_logic() -> void:
	day_night = DayNightCycleClass.new()
	wave_director = WaveDirector.new()
	inventory = InventorySystem.new()
	combat = CombatSystem.new()
	gather = GatherSystem.new()
	build_logic = BuildSystem.new()
	wave_gate = WaveDirectorGate.new()
	telemetry = Telemetry.new()

func _build_world() -> void:
	# Lighting modulator — tints the world below the HUD canvas layer.
	lighting = LightingAdapterScript.new()
	lighting.name = "Lighting"
	add_child(lighting)
	sector = SectorScene.instantiate()
	add_child(sector)
	hero = HeroScene.instantiate()
	hero.set_hero(DEFAULT_HERO_ID)
	hero.attach_sector(sector)
	add_child(hero)
	# Combat visuals layer — sibling so swing arcs render in world space.
	combat_visuals = CombatVisualsScript.new()
	combat_visuals.name = "CombatVisuals"
	add_child(combat_visuals)
	# Build overlay processes the cursor + click-to-place handshake.
	build_overlay = BuildOverlayScript.new()
	build_overlay.name = "BuildOverlay"
	add_child(build_overlay)

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = HudScene.instantiate()
	ui_layer.add_child(hud)
	# Inventory HUD anchors to the bottom band of the viewport.
	inventory_hud = InventoryHudScript.new()
	inventory_hud.name = "InventoryHud"
	inventory_hud.anchor_left = 0.0
	inventory_hud.anchor_right = 1.0
	inventory_hud.anchor_top = 1.0
	inventory_hud.anchor_bottom = 1.0
	inventory_hud.offset_top = -InventoryHudScript.BAND_HEIGHT
	inventory_hud.offset_bottom = 0.0
	ui_layer.add_child(inventory_hud)
	end_screen = EndScene.instantiate()
	ui_layer.add_child(end_screen)
	# Telemetry IO is a non-visual node — parent it under self so its
	# _process tick fires and _exit_tree flushes on shutdown.
	telemetry_io = TelemetryIoScript.new()
	telemetry_io.name = "TelemetryIO"
	add_child(telemetry_io)
	telemetry_io.attach(telemetry)

func _wire_signals() -> void:
	hud.bind(day_night)
	inventory_hud.bind(inventory)
	build_overlay.attach(sector, inventory, build_logic)
	combat_visuals.attach(combat)
	lighting.bind(day_night)
	wave_gate.bind(day_night, wave_director)
	wave_director.enemy_due.connect(_on_enemy_due)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	day_night.phase_changed.connect(_on_phase_changed)
	day_night.cycle_complete.connect(_on_cycle_complete)
	sector.core_destroyed.connect(_on_core_destroyed)
	hero.hero_downed.connect(_on_hero_downed)
	end_screen.restart_requested.connect(_on_restart_requested)
	build_overlay.place_requested.connect(_on_place_requested)
	build_logic.placed.connect(_on_placed)
	gather.gather_progress.connect(_on_gather_progress)
	gather.gather_completed.connect(_on_gather_completed)
	inventory.added_item.connect(_on_inventory_added)
	combat.damage_dealt.connect(_on_combat_damage)

func _start_run() -> void:
	GameState.reset()
	GameState.set_hero(DEFAULT_HERO_ID)
	sector.set_hero(DEFAULT_HERO_ID)
	sector.reset_core()
	hero.reset_hp()
	hero.reset_position()
	wave_director.reset()
	day_night.reset()
	inventory.reset()
	combat.reset()
	gather.reset()
	telemetry.reset()
	_resources_gathered = 0
	_enemies_felled = 0
	_nights_survived = 0
	for item in STARTER_ITEMS:
		inventory.add(item.id, int(item.count))
	# Default selection: slot 0 (hand axe). Equipping happens via the
	# inventory's selection-side effect.
	inventory.select_slot(0)
	end_screen.visible = false
	hud.visible = true
	inventory_hud.visible = true
	telemetry.start_run({
		"hero_id": GameState.hero_id,
		"max_nights": DayNight.MAX_NIGHTS,
	})

func _process(delta: float) -> void:
	# When the run is over, freeze ticks so the end-screen scrim doesn't
	# sit on top of a noisy world (cycle still advancing, wolves still
	# spawning). Restart re-enters via _start_run.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	day_night.tick(delta)
	wave_director.tick(delta)
	combat.tick(delta)
	if gather.is_active() and is_instance_valid(hero):
		var node = gather.active_node()
		if node != null and is_instance_valid(node):
			gather.tick(delta, hero.current_tile, node.current_tile, inventory.equipped_weapon())
	# Hold-to-gather: when E is held and the hero is next to a resource
	# node, kick off / refresh gathering. Releasing E cancels.
	if Input.is_action_pressed("gather"):
		_try_start_gather()
	elif Input.is_action_just_released("gather"):
		gather.cancel_active()
	# Hotbar 1..8 → select slot.
	for i in InventorySystem.SLOT_COUNT:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			inventory.select_slot(i)

func _unhandled_input(event: InputEvent) -> void:
	# Click-to-attack — only fires when no placeable is selected (the
	# build overlay handles the click in that case).
	if not (event is InputEventMouseButton):
		return
	# Mirror the _process gate: once the run is over, swallow inputs so
	# clicks on the end-screen scrim don't trigger swings (or telemetry
	# events) behind the UI.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click anywhere clears any active placeable preview.
		inventory.clear_selection()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var sel_id: String = inventory.selected_item_id()
	if not sel_id.is_empty() and Items.is_placeable(sel_id):
		# Build overlay owns left-click while a placeable is armed.
		return
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	var swing_result: Dictionary = combat.resolve_swing(hero.position, hero.facing, inventory.equipped_weapon(), enemies)
	if telemetry != null and swing_result.get("ok", false):
		telemetry.log("ability_cast", {
			"ability_id": "weapon_swing",
			"weapon_id": String(swing_result.get("weapon", "")),
			"hits": int((swing_result.get("hits", []) as Array).size()),
		})

# ── Gather plumbing ──────────────────────────────────────────────────
func _try_start_gather() -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	if gather.is_active():
		return
	# Find a resource node within 1 tile of the hero. Prefer the closest
	# in cardinal direction the hero is facing — keeps the interaction
	# predictable when two nodes are adjacent.
	var best: Node2D = null
	var best_d: int = 99
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as Node2D
		if rn == null or not is_instance_valid(rn):
			continue
		var d: int = sector.tile_distance(hero.current_tile, rn.current_tile)
		if d < best_d and d <= 1:
			best_d = d
			best = rn
	if best == null:
		return
	gather.start_gather(best, best.resource_kind_id(), best.hp, best.hp_max)

func _on_gather_progress(node_ref, hp_remaining: float, _hp_max: float) -> void:
	if node_ref != null and is_instance_valid(node_ref):
		node_ref.update_progress(hp_remaining)

func _on_gather_completed(node_ref, yields: Dictionary) -> void:
	var resource_kind: String = ""
	if node_ref != null and is_instance_valid(node_ref) and node_ref.has_method("resource_kind_id"):
		resource_kind = String(node_ref.resource_kind_id())
	for item_id in yields:
		var leftover: int = inventory.add(item_id, int(yields[item_id]))
		_resources_gathered += int(yields[item_id]) - leftover
		# Pickup-on-floor when inventory overflows is flagged in the
		# brief but out of MVP scope — leftover is logged and dropped.
		if leftover > 0:
			push_warning("Inventory full — %d %s left on the floor" % [leftover, item_id])
	if telemetry != null:
		telemetry.log("resource_gathered", {
			"resource_kind": resource_kind,
			"yields": yields.duplicate(),
		})
	if node_ref != null and is_instance_valid(node_ref):
		node_ref.deplete()

func _on_inventory_added(_item_id: String, _count: int) -> void:
	# Hook for future audio / VFX. Stat tally happens at gather_completed
	# so it doesn't double-count when the same item arrives via place
	# refunds, etc.
	pass

# ── Build plumbing ───────────────────────────────────────────────────
func _on_place_requested(item_id: String, tile: Vector2i) -> void:
	build_logic.place(item_id, tile, inventory, Callable(sector, "is_tile_walkable"))

func _on_placed(item_id: String, tile: Vector2i) -> void:
	var item: Dictionary = Items.get_item(item_id)
	var placeable_id: String = item.get("placeable_id", "")
	if placeable_id.is_empty():
		return
	if telemetry != null:
		telemetry.log("building_placed", {
			"item_id": item_id,
			"placeable_id": placeable_id,
			"tile_x": tile.x,
			"tile_y": tile.y,
		})
	var p: Node2D = PlaceableScene.instantiate()
	p.configure(placeable_id)
	p.attach_sector(sector)
	add_child(p)
	p.place_at_tile(tile)
	# After placing, if the player ran out of that item, clear the build
	# ghost so they don't see a "blocked because no resources" red ghost
	# trailing the cursor.
	if not inventory.has_at_least(item_id, 1):
		sector.clear_build_ghost()

# ── Combat plumbing ──────────────────────────────────────────────────
func _on_combat_damage(target_ref, amount: float) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	target_ref.damage(amount)

# ── Wave plumbing ────────────────────────────────────────────────────
func _on_enemy_due(enemy_type: String, slot_index: int) -> void:
	var entry_tiles: Array[Vector2i] = Sectors.ENEMY_ENTRY_TILES
	var entry_tile: Vector2i = entry_tiles[slot_index % entry_tiles.size()]
	var e: Node2D = EnemyScene.instantiate()
	e.configure(enemy_type)
	e.attach_sector(sector)
	e.died.connect(_on_enemy_died.bind(enemy_type))
	e.reached_core.connect(_on_enemy_reached_core)
	# Bind enemy_type so the telemetry hook knows what hit the hero
	# without re-reading the (possibly freed) enemy node.
	e.damaged_target.connect(_on_enemy_damaged_target.bind(enemy_type))
	add_child(e)
	e.place_at_tile(entry_tile)
	wave_director.note_enemy_spawned()

func _on_enemy_died(enemy: Node, enemy_type: String) -> void:
	wave_director.note_enemy_killed()
	_enemies_felled += 1
	if telemetry != null:
		telemetry.log("hero_killed_enemy", {
			"enemy_type": enemy_type,
		})

func _on_enemy_damaged_target(target_ref, amount: float, enemy_type: String) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	if not target_ref.is_in_group("hero"):
		return
	if telemetry == null:
		return
	telemetry.log("hero_damage_taken", {
		"amount": amount,
		"hp_after": float(target_ref.hp),
		"hp_max": float(target_ref.hp_max),
		"source_enemy_type": enemy_type,
	})

func _on_enemy_reached_core(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	sector.damage_core(float(enemy.data.damage))
	wave_director.note_enemy_killed()
	enemy.queue_free()

func _on_wave_started(round_index: int, composition: Dictionary) -> void:
	# Voice rule: archetype banner is the ALL-CAPS shout, e.g.
	#   "NIGHT 1 — PROBE"
	#   "NIGHT 3 — A BIG ONE INCOMING"
	# The HUD's NIGHT phase-change banner is suppressed so this is
	# the single banner the player sees at night-start.
	var shout: String = "NIGHT %d — %s" % [round_index, str(composition.get("banner", "RAID"))]
	hud.show_banner(shout, 2.5)
	if telemetry != null:
		var summary: Dictionary = {}
		for entry in composition.get("enemies", []):
			summary[String(entry.type)] = int(summary.get(entry.type, 0)) + int(entry.count)
		telemetry.log("wave_start", {
			"round_index": round_index,
			"archetype": String(composition.get("archetype", "")),
			"has_mini_boss": bool(composition.get("has_mini_boss", false)),
			"composition": summary,
		})

func _on_wave_ended(round_index: int) -> void:
	# Sweep any wolves still on the board — dawn ended the night, the
	# pack retreats. Keeps day-1-into-day-2 transitions clean.
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	_nights_survived += 1
	if telemetry != null:
		telemetry.log("wave_end", {
			"round_index": round_index,
			"nights_survived": _nights_survived,
		})

# ── Day/night plumbing ───────────────────────────────────────────────
func _on_phase_changed(_phase: int, _day_index: int) -> void:
	pass  # HUD listens directly; nothing for main to do.

func _on_cycle_complete(_nights: int) -> void:
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.set_stats(_nights_survived, _resources_gathered, _enemies_felled)
	end_screen.show_victory()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "victory",
			"nights_survived": _nights_survived,
			"resources_gathered": _resources_gathered,
			"enemies_felled": _enemies_felled,
		})

# ── Run-end plumbing ─────────────────────────────────────────────────
func _on_hero_downed() -> void:
	# Hero HP at 0 ends the run. The wave-defense build only banner-noted
	# this; survival treats hero death as defeat (no respawn for MVP).
	#
	# Defer so the rest of the in-flight signal chain settles before the
	# run is closed out. enemy._physics_process calls hero.damage() and
	# THEN emits damaged_target — without the defer, _run_defeat would
	# log run_end before the fatal damaged_target ever fires its
	# hero_damage_taken event, putting the events out of order in the
	# run file (and dropping the fatal hit if run_id were cleared).
	_run_defeat.call_deferred()

func _on_core_destroyed() -> void:
	# Same rationale as _on_hero_downed — defer for symmetry and to
	# avoid serializing run-end side-effects inside another module's
	# signal stack.
	_run_defeat.call_deferred()

func _run_defeat() -> void:
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.set_stats(_nights_survived, _resources_gathered, _enemies_felled)
	end_screen.show_defeat()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "defeat",
			"nights_survived": _nights_survived,
			"resources_gathered": _resources_gathered,
			"enemies_felled": _enemies_felled,
		})

func _on_restart_requested() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("placeables"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n): n.queue_free()
	sector.clear_build_ghost()
	# Re-build AStar from a clean slate (the placed walls + depleted
	# resource nodes mutated it; rebuilding is cheaper than tracking
	# every change to undo it).
	sector.rebuild_astar()
	_seed_world_resources()
	_start_run()

# ── World seeding ────────────────────────────────────────────────────
func _seed_world_resources() -> void:
	# Hand-crafted seed: a treeline north, a rock outcrop east, berry
	# bushes south of the lodge. Exact tile positions live here rather
	# than in data/sectors.gd because they're "where" decisions, not
	# "how the world is shaped" decisions — biome rectangles in sectors
	# describe the latter, this loop describes the former.
	var trees := [
		Vector2i(5, 2), Vector2i(7, 1), Vector2i(9, 2), Vector2i(12, 1),
		Vector2i(15, 2), Vector2i(17, 1), Vector2i(19, 2),
		Vector2i(6, 4), Vector2i(10, 4), Vector2i(14, 4), Vector2i(18, 4),
	]
	var rocks := [
		Vector2i(21, 8), Vector2i(22, 10), Vector2i(21, 12), Vector2i(23, 14),
		Vector2i(22, 16),
	]
	var bushes := [
		Vector2i(8, 19), Vector2i(11, 19), Vector2i(14, 19), Vector2i(17, 19),
	]
	for tile in trees:
		_spawn_resource("tree_pine", tile)
	for tile in rocks:
		_spawn_resource("rock_field", tile)
	for tile in bushes:
		_spawn_resource("berry_bush", tile)

func _spawn_resource(kind: String, tile: Vector2i) -> void:
	if not Sectors.is_tile_in_grid(tile) or Sectors.is_tile_protected(tile):
		return
	if not sector.is_tile_walkable(tile):
		return
	var n: Node2D = ResourceNodeScene.instantiate()
	n.configure(kind)
	n.attach_sector(sector)
	add_child(n)
	n.place_at_tile(tile)
