extends Node2D
##
## Boot script for the survival rebuild + M2. Builds logic modules,
## instantiates scene-tree adapters, generates the procgen world from
## the run config (BUF-144), applies effective_stats from the lodge
## upgrade tree (BUF-147), and wires signals between everything.
##
## Pure logic + data layers stay verbatim from their files. Only the
## adapter wiring lives here.

const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Items := preload("res://data/items.gd")
const Resources := preload("res://data/resources.gd")
const DayNight := preload("res://data/day_night.gd")
const Waves := preload("res://data/waves.gd")
const Weapons := preload("res://data/weapons.gd")
const RunEconomy := preload("res://data/run_economy.gd")
const DayNightCycleClass := preload("res://scripts/logic/day_night_cycle.gd")
const StatSystemClass := preload("res://scripts/logic/stat_system.gd")
const WorldGeneratorClass := preload("res://scripts/logic/world_generator.gd")
const WaveDirectorGate := preload("res://scripts/adapters/wave_director_gate.gd")
const LightingAdapterScript := preload("res://scripts/adapters/lighting_adapter.gd")
const InventoryHudScript := preload("res://scripts/adapters/inventory_hud.gd")
const BuildOverlayScript := preload("res://scripts/adapters/build_overlay.gd")
const CombatVisualsScript := preload("res://scripts/adapters/combat_visuals.gd")
const TelemetryIoScript := preload("res://scripts/adapters/telemetry_io.gd")
const WorldBuilderScript := preload("res://scripts/adapters/world_builder.gd")
const DebugOverlayScript := preload("res://scripts/adapters/debug_overlay.gd")
const DebugPanelScript := preload("res://scripts/adapters/debug_panel.gd")
const StatSystemTest := preload("res://scripts/tests/stat_system_test.gd")
const ProjectileScene := preload("res://scenes/projectile.tscn")

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const ResourceNodeScene := preload("res://scenes/resource_node.tscn")
const PlaceableScene := preload("res://scenes/placeable.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")

const SaveStateClass := preload("res://scripts/logic/save_state.gd")
const LODGE_SCENE_PATH := "res://scenes/lodge/lodge.tscn"
# Pause before the scene swap so the player sees what just happened —
# without a beat, victory/defeat reads as a tab switch rather than a
# story moment. The end-screen scrim covers the world during the wait.
#
# Bumped from the original 1.6s so the new Copy-seed button (BUF-145)
# is reachable. Any end-screen interaction (Copy seed, Run again)
# cancels the timer via player_engaged so the player can read + copy
# at their own pace. The seed is also surfaced in the lodge's
# last-watch row so missing the window isn't fatal.
const RUN_END_TO_LODGE_DELAY_SECONDS := 6.0
# Where dump_world() writes the WorldDef JSON during F3 debug mode.
const DEBUG_DUMP_DIR := "user://debug"

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
var world_builder = null
var debug_overlay = null
var debug_panel = null

# Run state.
var _resources_gathered: int = 0
var _enemies_felled: int = 0
var _nights_survived: int = 0
var _run_started_msec: int = 0
var _run_seed: int = 0
var _world_def: Dictionary = {}
var _effective_stats: Dictionary = {}
var _starter_items: Array = []
var _embers_awarded_this_run: int = 0
# Set to true when the player engages with the end-screen (Copy seed,
# any other interaction). The pending auto-transition reads this and
# bails so the seed-share UI sits open as long as the player wants it.
# "Run again" button advances directly via _on_restart_requested and
# ignores this flag.
var _run_end_auto_transition_cancelled: bool = false

const DEFAULT_HERO_ID := "Buffalo"

func _ready() -> void:
	randomize()
	# Hero + seed come from GameState (set by the run-start screen via
	# BUF-145). If neither is set — direct main.tscn launch with no
	# preceding run-start — fall back to defaults so the scene is still
	# runnable for development.
	var hero_id: String = GameState.hero_id if not GameState.hero_id.is_empty() else DEFAULT_HERO_ID
	GameState.set_hero(hero_id)
	_run_seed = GameState.run_seed if GameState.run_seed != 0 else WorldGeneratorClass.random_seed()
	GameState.run_seed = _run_seed
	# Variant fallback (BUF-129). run_start.gd is the canonical place to
	# roll a fresh variant on campaign start; this ensure_variant call
	# only rolls one if none is set, keeping a direct main.tscn launch
	# (skipping the run-start screen) functional without re-rolling on
	# every loop. Players who came in via run-start already have one set.
	SaveIo.ensure_variant(hero_id)
	# Compute effective stats from owned upgrades BEFORE anything else
	# touches base values — hero baseHealth, lodge HP, weapon scale, etc.
	_effective_stats = StatSystemClass.effective_stats(hero_id, SaveIo.owned_upgrades())
	_starter_items = _build_starter_items(hero_id)
	_build_logic()
	_build_world()
	_build_ui()
	_wire_signals()
	# World generation runs ONCE per run on day_index = 1 (with day-1
	# climate weights). The chunks stay constant across the run; the
	# lighting adapter pushes the cold-tint forward each successive
	# night so the world *visibly* deepens into winter (BUF-146).
	_generate_world(1)
	_apply_stats_to_systems()
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
	hero.set_hero(GameState.hero_id)
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
	# World builder spawns resource node Node2Ds from the WorldDef.
	world_builder = WorldBuilderScript.new()
	world_builder.name = "WorldBuilder"
	add_child(world_builder)
	world_builder.attach(sector, self)
	# Debug overlay (F3) — chunk lines drawn in world space.
	debug_overlay = DebugOverlayScript.new()
	debug_overlay.name = "DebugOverlay"
	add_child(debug_overlay)
	debug_overlay.attach(sector)

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
	# Debug panel (F3) — screen-space stats panel above the world overlay.
	debug_panel = DebugPanelScript.new()
	debug_panel.name = "DebugPanel"
	ui_layer.add_child(debug_panel)
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
	end_screen.player_engaged.connect(_cancel_run_end_transition)
	build_overlay.place_requested.connect(_on_place_requested)
	build_logic.placed.connect(_on_placed)
	gather.gather_progress.connect(_on_gather_progress)
	gather.gather_completed.connect(_on_gather_completed)
	gather.gather_cancelled.connect(_on_gather_cancelled)
	inventory.added_item.connect(_on_inventory_added)
	combat.damage_dealt.connect(_on_combat_damage)
	combat.projectile_requested.connect(_on_projectile_requested)
	combat.ammo_consumed.connect(_on_ammo_consumed)

# ── World generation (BUF-144) ───────────────────────────────────────
func _generate_world(day_index: int) -> void:
	var t0: int = Time.get_ticks_msec()
	_world_def = WorldGeneratorClass.generate(_run_seed, day_index, GameState.hero_id)
	var elapsed: int = Time.get_ticks_msec() - t0
	# Brief mandates <250 ms; a stamp + ~20 resource placements completes
	# in single-digit ms in practice. Warning fires only if generation
	# starts misbehaving so we catch perf regressions.
	if elapsed > 250:
		push_warning("WorldGenerator slow: %d ms (target <250)" % elapsed)
	if sector != null and sector.has_method("adopt_world"):
		sector.adopt_world(_world_def)
	if world_builder != null:
		world_builder.build_from(_world_def)
	if debug_overlay != null:
		debug_overlay.set_world(_world_def)
	if debug_panel != null:
		debug_panel.set_world(_world_def)

func _apply_stats_to_systems() -> void:
	# Stat dispatch (BUF-147). Each consumer reads what it cares about
	# from the effective_stats dict — no system reads the upgrade list
	# directly.
	var stats: Dictionary = _effective_stats
	if hero != null and is_instance_valid(hero) and hero.has_method("apply_stats"):
		hero.apply_stats(float(stats.hp_max), float(stats.move_speed))
	if combat != null:
		combat.set_stat_modifiers(
			float(stats.attack_damage),
			float(stats.attack_speed),
			float(stats.attack_range),
		)
	if gather != null:
		gather.set_speed_multiplier(float(stats.gather_speed))
	if sector != null:
		sector.reset_core(float(stats.lodge_hp_max))
	# Apply the inventory_slots upgrade BEFORE _start_run calls
	# inventory.reset() — reset() builds the slots array at the active
	# slot_count, so widening must happen first or the new slots won't
	# materialize until the second run after purchase.
	if inventory != null:
		inventory.set_slot_count(int(stats.inventory_slots))
	# Stamp the upgrade-modified ability cooldown into GameState so the
	# moment Q-bound abilities land (BUF-150-ish), they read it via the
	# existing set_signature_cooldown contract. Today no consumer fires
	# the ability — the upgrades disclose this in their description.
	# Setting the *max* (not the remaining) so cooldown ticks land at
	# the right ceiling whenever the resolver finally connects.
	GameState.set_signature_cooldown(0.0, float(stats.ability_cooldown))

func _build_starter_items(hero_id: String) -> Array:
	# Pick the best axe the player has unlocked at the lodge. Default
	# is hand_axe; iron_axe replaces it once unlocked; steel_axe replaces
	# both. Players also get spear / bow + arrows when unlocked. Wood
	# walls always seed at 4 so day 1 has something to build.
	var owned: Array = SaveIo.owned_upgrades()
	var unlocks: Dictionary = StatSystemClass.unlocks_from(owned)
	var axe_id: String = "hand_axe"
	if unlocks.has("iron_axe"):
		axe_id = "iron_axe"
	if unlocks.has("steel_axe"):
		axe_id = "steel_axe"
	var items: Array = [
		{"id": axe_id, "count": 1},
		{"id": "wood_wall", "count": 4},
	]
	# Spear in slot 2 if unlocked; bow + arrows after.
	if unlocks.has("spear"):
		items.append({"id": "spear", "count": 1})
	if unlocks.has("bow"):
		items.append({"id": "bow", "count": 1})
	if unlocks.has("arrow"):
		items.append({"id": "arrow", "count": 12})
	return items

func _start_run() -> void:
	# Snapshot identity before reset() so the same hero + seed survive
	# the phase / hp wipe that GameState.reset() applies.
	var preserved_hero: String = GameState.hero_id if not GameState.hero_id.is_empty() else DEFAULT_HERO_ID
	GameState.reset()
	GameState.set_hero(preserved_hero)
	GameState.run_seed = _run_seed
	# Re-stamp the upgrade-modified ability cooldown AFTER reset() (which
	# clears it via set_signature_cooldown(0, 0)). _apply_stats_to_systems
	# sets it pre-reset, but reset wipes it; without this re-stamp the
	# value lands at the wrong ceiling for the upcoming run.
	GameState.set_signature_cooldown(0.0, float(_effective_stats.get("ability_cooldown", 0.0)))
	sector.set_hero(GameState.hero_id)
	# Reset core uses the upgrade-scaled lodge_hp_max so the upgrade
	# applies immediately on a fresh run.
	sector.reset_core(float(_effective_stats.get("lodge_hp_max", Sectors.CORE_HEALTH)))
	hero.reset_hp()
	hero.reset_position()
	wave_director.reset()
	day_night.reset()
	inventory.reset()
	combat.reset()
	combat.set_stat_modifiers(
		float(_effective_stats.get("attack_damage", 1.0)),
		float(_effective_stats.get("attack_speed", 1.0)),
		float(_effective_stats.get("attack_range", 0.0)),
	)
	gather.reset()
	gather.set_speed_multiplier(float(_effective_stats.get("gather_speed", 1.0)))
	telemetry.reset()
	_resources_gathered = 0
	_enemies_felled = 0
	_nights_survived = 0
	_embers_awarded_this_run = 0
	_run_started_msec = Time.get_ticks_msec()
	for item in _starter_items:
		inventory.add(item.id, int(item.count))
	# Default selection: slot 0 (the equipped axe).
	inventory.select_slot(0)
	end_screen.visible = false
	hud.visible = true
	inventory_hud.visible = true
	telemetry.start_run({
		"hero_id": GameState.hero_id,
		"max_nights": DayNight.MAX_NIGHTS,
		"deck_composition": _starter_items.duplicate(true),
		"seed": _run_seed,
		"seed_string": WorldGeneratorClass.seed_to_string(_run_seed),
		"owned_upgrades": SaveIo.owned_upgrades().duplicate(),
	})

func _process(delta: float) -> void:
	# When the run is over, freeze ticks so the end-screen scrim doesn't
	# sit on top of a noisy world. Restart re-enters via _start_run.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	day_night.tick(delta)
	wave_director.tick(delta)
	combat.tick(delta)
	if gather.is_active() and is_instance_valid(hero):
		var node = gather.active_node()
		if node != null and is_instance_valid(node):
			gather.tick(delta, hero.current_tile, node.current_tile, inventory.equipped_weapon())
	if Input.is_action_pressed("gather"):
		_try_start_gather()
	elif Input.is_action_just_released("gather"):
		gather.cancel_active()
	# Only the first 8 slots have hotbar bindings (hotbar_1..hotbar_8 in
	# project.godot). Slots 9+ from the "Extra pouch" upgrade are
	# storage-only — clickable on the HUD but not hotkey-addressable.
	for i in min(8, inventory.slot_count):
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			inventory.select_slot(i)

func _unhandled_input(event: InputEvent) -> void:
	# F3 toggles the debug overlay (BUF-145). Captured here rather than
	# as a registered input action so we don't have to touch project.godot
	# for this dev-only toggle.
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_F3:
			if debug_overlay != null:
				debug_overlay.toggle()
			if debug_panel != null:
				debug_panel.toggle()
			return
		if k.pressed and k.keycode == KEY_F4:
			# F4 = dump current WorldDef to user://debug/<seed>.json so
			# the chunk pick / resource list can be inspected offline.
			_dump_world()
			return
		# BUF-147 acceptance: QA debug commands. F5 grants 5 embers
		# (lets the next lodge visit have something to spend without
		# grinding); F6 grants every authored upgrade (max-stack stat
		# composition test); Shift+F6 wipes the meta-progression so
		# the QA loop can re-test from scratch. F12 reruns the stat-
		# system composition test and prints to the Output panel.
		if k.pressed and k.keycode == KEY_F5:
			var balance: int = SaveIo.debug_grant_embers(5)
			print("debug: granted 5 embers (balance=%d)" % balance)
			return
		if k.pressed and k.keycode == KEY_F6:
			if k.shift_pressed:
				SaveIo.debug_clear_progression()
				print("debug: cleared embers + owned upgrades")
			else:
				var n: int = SaveIo.debug_grant_all_upgrades()
				print("debug: granted all upgrades (%d owned)" % n)
			return
		if k.pressed and k.keycode == KEY_F12:
			var report: Dictionary = StatSystemTest.run_all()
			StatSystemTest.print_results(report)
			return
	if not (event is InputEventMouseButton):
		return
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
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
	# Ammo count for ranged weapons. Bare hands / melee ignore it.
	var equipped: String = inventory.equipped_weapon()
	var ammo_count: int = 0
	if Weapons.is_ranged(equipped):
		var ammo_id: String = Weapons.ammo_for(equipped)
		# Inventory has has_at_least but no exact-count getter — count
		# slots with the ammo id.
		for slot in inventory.slots:
			if String(slot.get("item_id", "")) == ammo_id:
				ammo_count += int(slot.get("count", 0))
	var swing_result: Dictionary = combat.resolve_swing(hero.position, hero.facing, equipped, enemies, ammo_count)
	if telemetry != null and swing_result.get("ok", false):
		telemetry.log("ability_cast", {
			"ability_id": "weapon_swing",
			"weapon_id": String(swing_result.get("weapon", "")),
			"hits": int((swing_result.get("hits", []) as Array).size()),
			"ranged": bool(swing_result.get("ranged", false)),
		})

# ── Debug helpers (BUF-145) ──────────────────────────────────────────
func _dump_world() -> void:
	if _world_def.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DEBUG_DUMP_DIR)
	var seed_str: String = WorldGeneratorClass.seed_to_string(_run_seed)
	var path: String = "%s/world_%s.json" % [DEBUG_DUMP_DIR, seed_str]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("debug: could not open %s" % path)
		return
	# Vector2i / Vector2 don't json natively — flatten into [x, y] pairs.
	f.store_string(JSON.stringify(_flatten_world_for_json(_world_def), "\t"))
	f.close()
	print("debug: wrote ", path)

func _flatten_world_for_json(def: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for k in def.keys():
		var v = def[k]
		if v is Vector2i:
			copy[k] = [v.x, v.y]
		elif typeof(v) == TYPE_ARRAY and not (v as Array).is_empty() and (v as Array)[0] is Vector2i:
			var pts: Array = []
			for p in v:
				pts.append([p.x, p.y])
			copy[k] = pts
		elif k == "tiles":
			# Tile dicts pass through cleanly.
			copy[k] = v
		elif k == "resources":
			var rs: Array = []
			for r in v:
				rs.append({"kind": String(r.kind), "tile": [r.tile.x, r.tile.y]})
			copy[k] = rs
		elif k == "chunks":
			var cs: Array = []
			for c in v:
				cs.append({"chunk_pos": [c.chunk_pos.x, c.chunk_pos.y], "template_id": c.template_id, "climate": c.climate})
			copy[k] = cs
		else:
			copy[k] = v
	return copy

# ── Gather plumbing ──────────────────────────────────────────────────
func _try_start_gather() -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	if gather.is_active():
		return
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

func _on_gather_cancelled(node_ref) -> void:
	# Hero walked out of range. Hide the half-full progress bar so the
	# tree/rock visually reads as "untouched" again. Without this the
	# bar lingered in its last-cancelled state until the next gather.
	if node_ref != null and is_instance_valid(node_ref) and node_ref.has_method("clear_progress"):
		node_ref.clear_progress()

func _on_gather_completed(node_ref, yields: Dictionary) -> void:
	var resource_kind: String = ""
	if node_ref != null and is_instance_valid(node_ref) and node_ref.has_method("resource_kind_id"):
		resource_kind = String(node_ref.resource_kind_id())
	for item_id in yields:
		var leftover: int = inventory.add(item_id, int(yields[item_id]))
		_resources_gathered += int(yields[item_id]) - leftover
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
	if not inventory.has_at_least(item_id, 1):
		sector.clear_build_ghost()

# ── Combat plumbing ──────────────────────────────────────────────────
func _on_combat_damage(target_ref, amount: float) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	target_ref.damage(amount)

func _on_projectile_requested(_weapon_id: String, origin: Vector2, direction: Vector2, range_px: float, damage: float, speed_px: float) -> void:
	# Spawn an arrow Node2D at the hero's position. Hits roll in via
	# the projectile's own hit_target signal.
	var arrow: Node2D = ProjectileScene.instantiate()
	add_child(arrow)
	arrow.position = origin
	arrow.configure(direction, range_px, damage, speed_px)
	arrow.hit_target.connect(_on_projectile_hit)

func _on_projectile_hit(target_ref, amount: float) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	# Route through combat.damage_dealt so the same listeners that
	# handle melee hits (damage application + floating-number visuals)
	# fire for ranged hits too. Without this, bow hits applied damage
	# but never showed the floating number, since combat_visuals only
	# listens to combat.damage_dealt.
	combat.damage_dealt.emit(target_ref, amount)

func _on_ammo_consumed(item_id: String, count: int) -> void:
	if item_id.is_empty() or count <= 0:
		return
	inventory.remove_item(item_id, count)

# ── Wave plumbing ────────────────────────────────────────────────────
func _on_enemy_due(enemy_type: String, slot_index: int) -> void:
	var entry_tiles: Array[Vector2i] = Sectors.ENEMY_ENTRY_TILES
	var entry_tile: Vector2i = entry_tiles[slot_index % entry_tiles.size()]
	var e: Node2D = EnemyScene.instantiate()
	e.configure(enemy_type, Waves.stat_scale_for(wave_director.round_index))
	e.attach_sector(sector)
	e.died.connect(_on_enemy_died.bind(enemy_type))
	e.reached_core.connect(_on_enemy_reached_core)
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
	pass

func _on_cycle_complete(nights: int) -> void:
	# Defer so the rest of this frame's _process can finish without
	# events landing in the buffer behind run_end.
	_run_victory.call_deferred(nights)

func _run_victory(_nights: int) -> void:
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.set_stats(_nights_survived, _resources_gathered, _enemies_felled)
	end_screen.set_seed(_run_seed)
	_award_embers(SaveStateClass.OUTCOME_VICTORY)
	end_screen.set_embers_earned(_embers_awarded_this_run)
	end_screen.show_victory()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "victory",
			"nights_survived": _nights_survived,
			"resources_gathered": _resources_gathered,
			"enemies_felled": _enemies_felled,
			"embers_earned": _embers_awarded_this_run,
		})
	_record_run_and_go_to_lodge(SaveStateClass.OUTCOME_VICTORY)

# ── Run-end plumbing ─────────────────────────────────────────────────
func _on_hero_downed() -> void:
	_run_defeat.call_deferred()

func _on_core_destroyed() -> void:
	_run_defeat.call_deferred()

func _run_defeat() -> void:
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.set_stats(_nights_survived, _resources_gathered, _enemies_felled)
	end_screen.set_seed(_run_seed)
	_award_embers(SaveStateClass.OUTCOME_DEFEAT)
	end_screen.set_embers_earned(_embers_awarded_this_run)
	end_screen.show_defeat()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "defeat",
			"nights_survived": _nights_survived,
			"resources_gathered": _resources_gathered,
			"enemies_felled": _enemies_felled,
			"embers_earned": _embers_awarded_this_run,
		})
	_record_run_and_go_to_lodge(SaveStateClass.OUTCOME_DEFEAT)

func _award_embers(outcome: String) -> void:
	# Single-shot per run. Call only from victory/defeat paths.
	var amount: int = RunEconomy.award_for_run(outcome, _nights_survived, _resources_gathered, _enemies_felled)
	_embers_awarded_this_run = amount
	if amount > 0:
		SaveIo.add_embers(amount)
	if telemetry != null:
		telemetry.log("ember_earned", {
			"outcome": outcome,
			"amount": amount,
			"nights_survived": _nights_survived,
			"resources_gathered": _resources_gathered,
			"enemies_felled": _enemies_felled,
		})

func _record_run_and_go_to_lodge(outcome: String) -> void:
	var duration: float = float(Time.get_ticks_msec() - _run_started_msec) / 1000.0
	SaveIo.record_run(
		GameState.hero_id,
		outcome,
		_nights_survived,
		_resources_gathered,
		_enemies_felled,
		duration,
		_run_seed,
	)
	# Auto-transition reads _run_end_auto_transition_cancelled so the
	# end-screen Copy button + any future end-screen interactions can
	# stop it. SceneTreeTimer can't be unregistered, so we use a flag.
	_run_end_auto_transition_cancelled = false
	get_tree().create_timer(RUN_END_TO_LODGE_DELAY_SECONDS).timeout.connect(_auto_transition_to_lodge)

func _cancel_run_end_transition() -> void:
	# Fired by end_screen.player_engaged when the player clicks Copy
	# seed (or Run again, but that path advances manually anyway). Lets
	# the player sit on the end screen as long as they want.
	_run_end_auto_transition_cancelled = true

func _auto_transition_to_lodge() -> void:
	if _run_end_auto_transition_cancelled:
		return
	get_tree().change_scene_to_file(LODGE_SCENE_PATH)

func _on_restart_requested() -> void:
	# Manual "Run again" — advance directly, regardless of the auto-
	# transition flag.
	get_tree().change_scene_to_file(LODGE_SCENE_PATH)
