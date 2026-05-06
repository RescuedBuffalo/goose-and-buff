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
const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const DayNightCycleClass := preload("res://scripts/logic/day_night_cycle.gd")
const StatSystemClass := preload("res://scripts/logic/stat_system.gd")
const WorldGeneratorClass := preload("res://scripts/logic/world_generator.gd")
const AbilityResolverClass := preload("res://scripts/logic/ability_resolver.gd")
const WaveDirectorGate := preload("res://scripts/adapters/wave_director_gate.gd")
const LightingAdapterScript := preload("res://scripts/adapters/lighting_adapter.gd")
const InventoryHudScript := preload("res://scripts/adapters/inventory_hud.gd")
const BuildOverlayScript := preload("res://scripts/adapters/build_overlay.gd")
const CombatVisualsScript := preload("res://scripts/adapters/combat_visuals.gd")
const TelemetryIoScript := preload("res://scripts/adapters/telemetry_io.gd")
const WorldBuilderScript := preload("res://scripts/adapters/world_builder.gd")
const DebugOverlayScript := preload("res://scripts/adapters/debug_overlay.gd")
const DebugPanelScript := preload("res://scripts/adapters/debug_panel.gd")
const ReplicationScript := preload("res://scripts/adapters/replication.gd")
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
# `hero` always points at the *local* player's hero. In solo mode this
# is the only hero; in multiplayer it's the one this peer is driving.
# Other peers' heroes live on `replication.heroes_by_peer` and render as
# remote puppets (no local input authority, position-overridden by RPCs).
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
var replication = null

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

# ── Multiplayer run state ───────────────────────────────────────────────
# Per-peer hero info that's only relevant in multiplayer. Keys by peer_id.
# The replication adapter owns the hero node refs themselves; main holds
# only the run-flavored state (downed timers, in-combat status, AI).
var _peer_hero_in_combat: Dictionary = {}  # peer_id → bool
var _wave_first_hit_peer: int = 0  # 0 = no wave active or no first-hit chosen
var _wave_visible_to: Array = []  # peer_ids that have line-of-sight on the wave
var _veiled_composition: Dictionary = {}  # last full composition for veil-on-LOS
var _help_ability_cooldowns: Dictionary = {}  # peer_id → seconds remaining
var _front_rotation_index: int = 0
var _revive_hold_target: int = 0  # peer_id of revive target the local hero is currently reviving
var _revive_hold_seconds: float = 0.0

const DEFAULT_HERO_ID := "Buffalo"

func _ready() -> void:
	randomize()
	# Hero + seed come from GameState (set by the run-start screen via
	# BUF-145). If neither is set — direct main.tscn launch with no
	# preceding run-start — fall back to defaults so the scene is still
	# runnable for development.
	#
	# In multiplayer, MpIo.run_started broadcasts the host's seed +
	# hero assignments to every peer; GameState.set_run_config has
	# already been applied by the time we reach _ready, so reading from
	# GameState gives the same values on every machine.
	var hero_id: String = GameState.hero_id if not GameState.hero_id.is_empty() else DEFAULT_HERO_ID
	GameState.set_hero(hero_id)
	_run_seed = GameState.run_seed if GameState.run_seed != 0 else WorldGeneratorClass.random_seed()
	GameState.run_seed = _run_seed
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
	#
	# Determinism guarantee (BUF-151): same seed produces identical
	# world on every machine because world_generator is pure (uses a
	# locally-constructed RandomNumberGenerator and never reaches into
	# engine globals). Host broadcasts the seed; clients regenerate
	# locally rather than syncing tile data over the wire.
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
	# Replication is the multiplayer glue — spawn-per-peer, position
	# sync, RPC routing for combat. It's the only place RPCs live for
	# this scene; both pure logic and existing adapters stay
	# network-naive. The Replication node MUST be named the same on
	# every peer for NodePath-based RPC resolution.
	replication = ReplicationScript.new()
	replication.name = "Replication"
	add_child(replication)
	replication.attach(self, sector)
	replication.spawn_heroes_for_run()
	# Local hero is always the one this peer drives. In solo it's the
	# only one; in multiplayer it's whichever peer_id we are.
	hero = replication.local_hero()
	# Camera enabled only on the local hero — remote puppets have their
	# camera node parented but disabled in apply_remote_pose. Set the
	# local hero's camera as current here so launching solo + multi
	# share the same activation path.
	if hero != null and hero.has_node("Camera"):
		(hero.get_node("Camera") as Camera2D).enabled = true
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
	# Defeat in solo = local hero downed. Multiplayer doesn't end on a
	# single hero going down — the run ends only when the lodge falls or
	# every hero is fallen at once. Wire downed → defeat only in solo.
	for h in replication.all_heroes():
		h.hero_downed.connect(_on_hero_downed.bind(int(h.get_meta("peer_id", 0))))
		h.hero_fallen.connect(_on_hero_fallen.bind(int(h.get_meta("peer_id", 0))))
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
	# Multiplayer-only wiring: peer connection events for the seasonal-
	# frame banner copy + AI placeholder lifecycle (BUF-155).
	if MpIo.is_multiplayer():
		MpIo.peer_state_changed.connect(_on_peer_state_changed)

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
	#
	# Multiplayer note: stats here are the *local* peer's, computed from
	# their lodge upgrade tree. Each peer applies their own stats to
	# their own hero. Combat-system stat modifiers stay per-peer too —
	# attack_speed scales the *visual* swing cooldown locally; the host
	# resolves hits with the swinging peer's modifiers as included in
	# the swing intent (see host_resolve_remote_swing).
	var stats: Dictionary = _effective_stats
	if hero != null and is_instance_valid(hero) and hero.has_method("apply_stats"):
		hero.apply_stats(float(stats.hp_max), float(stats.move_speed))
	# Remote heroes default to their hero-data baseHealth / moveSpeed
	# until / unless their owning peer broadcasts modifiers. Skipping
	# stat application for them keeps the v1 implementation simple.
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
	# Seed wave_director with the run seed so every peer rolls the
	# same archetype on round 2 (BUF-151 determinism). The set_seed
	# call must happen *after* reset() — reset doesn't clear _rng but
	# we want a fresh RNG state anyway.
	wave_director.set_seed(_run_seed)
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
	# Logic ticks. In multiplayer, day_night + wave_director are still
	# *driven* on every peer to keep visible UI in sync — they're pure
	# functions of (start time, dt) given the same starting seed and
	# tick cadence. Wave start/end is broadcast by the host's
	# wave_director_gate so spawn timing matches even across small dt
	# drift. The host alone owns enemy spawning (see _on_enemy_due).
	day_night.tick(delta)
	wave_director.tick(delta)
	combat.tick(delta)
	# Position sync — local hero pose → peers, host enemy positions → all.
	if replication != null:
		replication.tick_position_sync(delta)
	# Help-ability cooldowns tick on the local peer for the local HUD.
	if not _help_ability_cooldowns.is_empty():
		var local_pid: int = MpIo.local_peer_id if MpIo.is_multiplayer() else 1
		var cd_remaining: float = float(_help_ability_cooldowns.get(local_pid, 0.0))
		if cd_remaining > 0.0:
			_help_ability_cooldowns[local_pid] = max(0.0, cd_remaining - delta)
	# Downed-timer enforcement (host-only) — when a downed hero's timer
	# hits zero without revive, transition them to fallen. Clients see
	# the same transition via replication broadcast.
	if MpIo.is_host() or not MpIo.is_multiplayer():
		_tick_downed_timers(delta)
	_tick_revive_input(delta)
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
	# Q fires the hero's signature ability (Charge / Dive / Snatch).
	# Cooldown is GameState.signature_cooldown — ticked here so the
	# rail in the HUD has live feedback.
	if GameState.signature_cooldown > 0.0:
		GameState.set_signature_cooldown(max(0.0, GameState.signature_cooldown - delta), GameState.signature_cooldown_max)
	if Input.is_action_just_pressed("signature_ability"):
		_try_fire_signature_ability()
	# Track in-combat per peer so the HUD's portrait pulse for non-
	# first-hit teammates only fires when there's actually a wave on
	# their friend (BUF-153). Host computes; clients render off broadcast.
	if MpIo.is_host() or not MpIo.is_multiplayer():
		_recompute_first_hit_visibility()

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
	# Help-ability targeting (BUF-154). When E is held and the local
	# hero clicks on a teammate's portrait or directly on the teammate,
	# fire the help ability instead of swinging. The portrait pulse +
	# clickable region lives in the HUD; here we accept clicks in world
	# space too as an alternate "click on the friend" path.
	if Input.is_action_pressed("help_ability"):
		var target_peer: int = _help_target_peer_at(get_global_mouse_position())
		if target_peer != 0:
			_request_help_ability(target_peer)
			return
	var sel_id: String = inventory.selected_item_id()
	if not sel_id.is_empty() and Items.is_placeable(sel_id):
		# Build overlay owns left-click while a placeable is armed.
		return
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	var enemies: Array = _gather_enemy_refs()
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
	# Multiplayer client: send swing intent to host, who re-runs the
	# resolver against the host-authoritative enemy list and broadcasts
	# damage_dealt back. The local hero gets a swing arc immediately
	# from the local combat.resolve_swing call — that's purely visual,
	# damage application happens off the broadcast.
	if MpIo.is_multiplayer() and not MpIo.is_host():
		# Local visual flash — emit swing_started so combat_visuals draws
		# the arc immediately. Don't apply damage; host will broadcast.
		var weapon: Dictionary = Weapons.get_weapon(equipped)
		var dir: Vector2 = hero.facing.normalized() if hero.facing.length_squared() > 0.0001 else Vector2.RIGHT
		var range_tiles: float = float(weapon.range_tiles)
		var length_px: float = range_tiles * 35.0
		var half_angle_rad: float = deg_to_rad(float(weapon.arc_degrees) * 0.5)
		# Ranged: deduct one arrow from the local inventory before
		# firing. The host doesn't touch the swinger's inventory (see
		# host_resolve_remote_swing — ammo_consumed is intentionally
		# unwired). Without this local debit, clients would shoot
		# unlimited arrows. Skip the intent if we're already empty so a
		# trigger-mash doesn't spawn projectiles the resolver will reject.
		if Weapons.is_ranged(equipped):
			if ammo_count < 1:
				return
			var ammo_id: String = Weapons.ammo_for(equipped)
			if not ammo_id.is_empty():
				inventory.remove_item(ammo_id, 1)
		combat.swing_started.emit(equipped, hero.position, dir, length_px, half_angle_rad)
		replication.client_request_swing(equipped, hero.position, hero.facing, ammo_count)
		return
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
	# Multiplayer host: route damage through replication so clients see
	# the same hp drop + death animation. Solo / client: apply locally.
	if MpIo.is_host():
		replication.host_apply_enemy_damage(target_ref, amount)
	else:
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
	# Multiplayer: only the host's WaveDirector should fire enemy_due
	# transitions. Clients run the wave_director locally for HUD timing
	# but they ignore enemy_due so they don't double-spawn — replication
	# RPCs handle the visible enemy node creation on clients.
	if MpIo.is_multiplayer() and not MpIo.is_host():
		return
	var stat_scale: Dictionary = Waves.stat_scale_for(wave_director.round_index)
	var e: Node2D = replication.host_spawn_enemy(enemy_type, slot_index, stat_scale)
	if e == null:
		return
	# Host bookkeeping wires die / reach-core / damage-target into the
	# host-only counters. Clients don't run these handlers; their puppet
	# enemies clean themselves up via the damage-broadcast path.
	e.died.connect(_on_enemy_died.bind(enemy_type))
	e.reached_core.connect(_on_enemy_reached_core)
	e.damaged_target.connect(_on_enemy_damaged_target.bind(enemy_type))
	# wants_to_damage is the application surface — the host applies the
	# hit, routing through replication when the target is a remote-owned
	# hero so the owning client sees the damage too. Solo collapses to a
	# direct .damage() call.
	e.wants_to_damage.connect(_on_enemy_wants_to_damage)
	wave_director.note_enemy_spawned()

func _on_enemy_died(enemy: Node, enemy_type: String) -> void:
	wave_director.note_enemy_killed()
	_enemies_felled += 1
	if telemetry != null:
		telemetry.log("hero_killed_enemy", {
			"enemy_type": enemy_type,
		})

func _on_enemy_wants_to_damage(target_ref, amount: float) -> void:
	# Apply enemy-attack damage. In multiplayer, hero targets must go
	# through replication so the owning peer sees the hit; without this,
	# the host's local `target.damage()` only mutates the host's puppet
	# of a client's hero and the owning peer keeps full HP. Lodge core,
	# units, and other non-hero targets apply directly — they live on
	# the host side and broadcast their state separately.
	if target_ref == null or not is_instance_valid(target_ref):
		return
	if MpIo.is_host() and target_ref.is_in_group("hero"):
		var pid: int = int(target_ref.get_meta("peer_id", 0))
		if pid != 0:
			replication.host_apply_hero_damage(pid, amount)
			return
	target_ref.damage(amount)

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
	# Pick first-hit hero for this wave (BUF-153). Only the host
	# computes; clients wait for the broadcast so the spine mechanic's
	# veil decision is host-authoritative. In solo, MpIo.is_host() is
	# false (no peer bound), so we fall through to the local pick.
	if MpIo.is_host() or not MpIo.is_multiplayer():
		_wave_first_hit_peer = _pick_first_hit_peer()
		_wave_visible_to = [_wave_first_hit_peer] if _wave_first_hit_peer != 0 else []
		_veiled_composition = composition.duplicate(true)
		if MpIo.is_host():
			replication.rpc("_rpc_wave_state", _wave_first_hit_peer, composition)
	else:
		# Client: the host's RPC will overwrite _wave_first_hit_peer
		# in a moment. Stage the composition so the local banner can
		# render once the host call lands.
		_veiled_composition = composition.duplicate(true)
	# Voice rule: the call-out for the first-hit hero uses seasonal-
	# frame language ("the cold comes from the north") rather than
	# "wave incoming". Non-first-hit heroes get only "in combat" — the
	# HUD veil keeps their composition hidden until they walk to it.
	var shout: String = ""
	var first_hit_hero_id: String = MpIo.resolve_hero_for_peer(_wave_first_hit_peer)
	if MpIo.is_multiplayer() and _wave_first_hit_peer != MpIo.local_peer_id and _wave_first_hit_peer != 0:
		shout = "%s is in combat. Listen for the call." % first_hit_hero_id
	else:
		var direction: String = _front_direction_for(_front_rotation_index)
		shout = "The cold comes from the %s — %s" % [direction, str(composition.get("banner", "RAID")).to_lower()]
	hud.show_banner(shout, 3.0)
	if telemetry != null:
		var summary: Dictionary = {}
		for entry in composition.get("enemies", []):
			summary[String(entry.type)] = int(summary.get(entry.type, 0)) + int(entry.count)
		telemetry.log("wave_start", {
			"round_index": round_index,
			"archetype": String(composition.get("archetype", "")),
			"has_mini_boss": bool(composition.get("has_mini_boss", false)),
			"composition": summary,
			"first_hit_peer": _wave_first_hit_peer,
			"first_hit_hero_id": first_hit_hero_id,
		})
		telemetry.log("wave_first_hit_hero", {
			"peer_id": _wave_first_hit_peer,
			"hero_id": first_hit_hero_id,
			"round_index": round_index,
		})
	# Rotate the front for the next wave. Doing this *after* the pick
	# means each wave fires in a different direction across a 3-night
	# run.
	_front_rotation_index = (_front_rotation_index + 1) % MultiplayerDataClass.FRONT_ROTATION.size()

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
func _on_phase_changed(phase: int, _day_index: int) -> void:
	# Dawn respawn for fallen heroes (BUF-152). A hero whose downed
	# timer expired without revive is rendered as kneeling at the
	# lodge; at the next dawn the host pushes a revive at
	# FALLEN_RESPAWN_HP_RATIO so they can keep playing the run. Without
	# this, the first hero to fall is permanently removed from the
	# watch unless every hero falls at once (which ends the run).
	# Solo also runs this — single-hero solo can't trigger it (a downed
	# hero ends the run), but a future "AI ally" mode would.
	if phase != DayNightCycleClass.Phase.DAWN:
		return
	if not (MpIo.is_host() or not MpIo.is_multiplayer()):
		return
	for h in replication.all_heroes():
		if h == null or not is_instance_valid(h):
			continue
		if not bool(h.get("is_fallen")):
			continue
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == 0:
			continue
		# Snap them back to the lodge so the watch reads as one body
		# again, then broadcast the revive at the configured ratio.
		var spawn_world: Vector2 = sector.tile_to_world(Sectors.SPAWN_TILE)
		h.position = spawn_world
		h.current_tile = Sectors.SPAWN_TILE
		replication.host_mark_hero_revived(pid, MultiplayerDataClass.FALLEN_RESPAWN_HP_RATIO)
		if telemetry != null:
			telemetry.log("hero_dawn_respawn", {"peer_id": pid})

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
func _on_hero_downed(peer_id: int) -> void:
	# Solo: a downed local hero ends the run immediately (M2 contract).
	# Multiplayer: a single downed hero starts a 30s revive timer; the
	# run only ends when every hero is fallen at once or the lodge falls.
	if telemetry != null:
		telemetry.log("hero_downed", {"peer_id": peer_id})
	if not MpIo.is_multiplayer():
		_run_defeat.call_deferred()

func _on_hero_fallen(peer_id: int) -> void:
	# Fired by hero adapter when the downed timer expires without a
	# revive. In multiplayer: respawn at lodge at FALLEN_RESPAWN_HP_RATIO
	# at the next dawn (handled in _on_phase_changed). If every hero is
	# fallen at once, end the run.
	if telemetry != null:
		telemetry.log("hero_fallen", {"peer_id": peer_id})
	if MpIo.is_multiplayer() and _every_hero_fallen():
		_run_defeat.call_deferred()

func _every_hero_fallen() -> bool:
	for h in replication.all_heroes():
		if not bool(h.get("is_fallen")):
			return false
	return true

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

# ── Multiplayer helpers ────────────────────────────────────────────────

func _gather_enemy_refs() -> Array:
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	return enemies

func _tick_downed_timers(_delta: float) -> void:
	# Per-frame check: any host-tracked hero whose downed timer hit zero
	# without revive transitions to fallen via replication broadcast.
	for h in replication.all_heroes():
		if h == null or not is_instance_valid(h):
			continue
		if not bool(h.get("is_downed")):
			continue
		if bool(h.get("is_fallen")):
			continue
		var rem_val = h.get("downed_seconds_remaining")
		var remaining: float = float(rem_val) if rem_val != null else 0.0
		if remaining > 0.0:
			continue
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == 0:
			continue
		replication.host_mark_hero_fallen(pid)

func _tick_revive_input(delta: float) -> void:
	# Local hero holding R near a downed teammate accumulates progress.
	# Once the hold reaches REVIVE_HOLD_SECONDS, fire revive intent.
	if hero == null or not is_instance_valid(hero) or bool(hero.get("is_downed")):
		_revive_hold_target = 0
		_revive_hold_seconds = 0.0
		_clear_visible_revive_progress()
		return
	if not Input.is_action_pressed("revive"):
		_revive_hold_target = 0
		_revive_hold_seconds = 0.0
		_clear_visible_revive_progress()
		return
	# Find the closest downed teammate within REVIVE_RANGE_TILES.
	var target: Node2D = _nearest_downed_teammate()
	if target == null:
		_revive_hold_target = 0
		_revive_hold_seconds = 0.0
		_clear_visible_revive_progress()
		return
	var target_pid: int = int(target.get_meta("peer_id", 0))
	if target_pid != _revive_hold_target:
		_revive_hold_target = target_pid
		_revive_hold_seconds = 0.0
	_revive_hold_seconds += delta
	# Surface progress on the target so its revive ring fills as the
	# hold accumulates. The target may be a remote puppet — that's fine,
	# the ring is a local visual hint, not networked state.
	target.revive_progress_seconds = _revive_hold_seconds
	target.queue_redraw()
	if _revive_hold_seconds >= MultiplayerDataClass.REVIVE_HOLD_SECONDS:
		_revive_hold_seconds = 0.0
		_revive_hold_target = 0
		target.revive_progress_seconds = 0.0
		target.queue_redraw()
		# Issue revive request — host arbitrates and broadcasts.
		if MpIo.is_multiplayer():
			replication.client_request_revive(target_pid)
		else:
			# Solo: a local revive doesn't really happen (single hero),
			# but keep the path defined for completeness.
			host_resolve_revive(1, target_pid)

func _clear_visible_revive_progress() -> void:
	for h in replication.all_heroes():
		var rp_val = h.get("revive_progress_seconds") if h != null and is_instance_valid(h) else null
		if rp_val != null and float(rp_val) != 0.0:
			h.revive_progress_seconds = 0.0
			h.queue_redraw()

func _nearest_downed_teammate() -> Node2D:
	if hero == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	var hero_tile: Vector2i = hero.current_tile
	for h in replication.all_heroes():
		if h == hero:
			continue
		if not bool(h.get("is_downed")):
			continue
		# Fallen heroes can't be revived in place — they wait until dawn.
		if bool(h.get("is_fallen")):
			continue
		var d: int = sector.tile_distance(hero_tile, h.current_tile)
		if d > MultiplayerDataClass.REVIVE_RANGE_TILES:
			continue
		if float(d) < best_d:
			best_d = float(d)
			best = h
	return best

# ── Help abilities (BUF-154) ───────────────────────────────────────────

func _help_target_peer_at(world_pos: Vector2) -> int:
	# Returns the peer_id of a teammate near the click, or 0 if none.
	# Used for the "click on the friend" alternate to portrait-click
	# targeting. HUD also calls request_help_ability_at_peer directly
	# for portrait clicks.
	if hero == null:
		return 0
	for h in replication.all_heroes():
		if h == hero:
			continue
		if not is_instance_valid(h):
			continue
		if (h.position - world_pos).length() < 32.0:
			return int(h.get_meta("peer_id", 0))
	# Quick-target: double-tap E (pressed twice this frame) picks the
	# most-in-combat teammate. Held-only acts as targeting cursor.
	if Input.is_action_just_pressed("help_ability"):
		return _quick_target_most_in_combat_peer()
	return 0

func _quick_target_most_in_combat_peer() -> int:
	# Picks the peer marked first-hit-hero this wave (the spine
	# mechanic's "most in combat") if any; else 0.
	if _wave_first_hit_peer != 0:
		return _wave_first_hit_peer
	return 0

func _request_help_ability(target_peer: int) -> void:
	# Local-side gate: cooldown check, valid target, alive caster.
	if hero == null or bool(hero.get("is_downed")):
		return
	var local_pid: int = MpIo.local_peer_id if MpIo.is_multiplayer() else 1
	var cd: float = float(_help_ability_cooldowns.get(local_pid, 0.0))
	if cd > 0.0:
		return
	if target_peer == local_pid or target_peer == 0:
		return
	# Stamp cooldown locally for HUD feedback. Host validates again.
	_help_ability_cooldowns[local_pid] = MultiplayerDataClass.HELP_ABILITY_COOLDOWN
	if MpIo.is_multiplayer():
		replication.client_request_help_ability(target_peer)
	else:
		# Solo path is a no-op — there are no teammates — but keep the
		# call defined for testability.
		pass

# Host-only resolution paths. RPCs in replication.gd route here for
# clients; the host's local-side calls them directly.

func host_resolve_remote_swing(peer_id: int, weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int) -> void:
	# Run the swing on the host using the requesting peer's facing /
	# weapon. Note: the host's own combat.tick handles cooldown for the
	# host's local hero — for remote peers we don't track per-peer
	# cooldown (clients gate themselves with their local CombatSystem).
	if not MpIo.is_host():
		return
	var enemies: Array = _gather_enemy_refs()
	var caster_hero: Node2D = replication.hero_for_peer(peer_id)
	if caster_hero == null or not is_instance_valid(caster_hero):
		return
	# Use a fresh CombatSystem for client swings so the host's combat
	# cooldown isn't blocked by a remote peer's swing. Stat modifiers
	# default to 1.0 — close enough for v1; per-peer mods are M5 work.
	var temp_combat := CombatSystem.new()
	# Connect damage_dealt + projectile_requested + swing_started to the
	# same handlers that the host's main.gd uses, so the host applies
	# damage and broadcasts via replication.
	#
	# Ammo: deliberately NOT connected. The remote peer owns its own
	# inventory; charging a remote bow shot to the host's inventory
	# would drain the host's arrows whenever a client fires (and the
	# client would never see its own count drop, since the swing intent
	# never touches local inventory either). Clients deduct ammo
	# locally before sending the intent; see the client-side swing
	# branch in _unhandled_input.
	temp_combat.damage_dealt.connect(_on_combat_damage)
	temp_combat.projectile_requested.connect(_on_projectile_requested)
	# Mirror swing_started to the visual layer so the host sees the
	# remote peer's swing arc (and so do the other clients via the
	# replication broadcast, since combat_visuals listens locally).
	temp_combat.swing_started.connect(combat.swing_started.emit)
	temp_combat.resolve_swing(origin, facing, weapon_id, enemies, ammo_count)

func host_resolve_revive(caster_peer: int, target_peer: int) -> void:
	if not (MpIo.is_host() or not MpIo.is_multiplayer()):
		return
	var caster: Node2D = replication.hero_for_peer(caster_peer)
	var target: Node2D = replication.hero_for_peer(target_peer)
	if caster == null or target == null:
		return
	if not bool(target.get("is_downed")) or bool(target.get("is_fallen")):
		return
	# Validate range — caster must still be within REVIVE_RANGE_TILES.
	if sector.tile_distance(caster.current_tile, target.current_tile) > MultiplayerDataClass.REVIVE_RANGE_TILES:
		return
	replication.host_mark_hero_revived(target_peer, MultiplayerDataClass.FALLEN_RESPAWN_HP_RATIO)
	if telemetry != null:
		telemetry.log("hero_revived", {"caster_peer": caster_peer, "target_peer": target_peer})

func host_resolve_help_ability(caster_peer: int, target_peer: int) -> void:
	if not MpIo.is_host():
		return
	var caster: Node2D = replication.hero_for_peer(caster_peer)
	var target: Node2D = replication.hero_for_peer(target_peer)
	if caster == null or target == null:
		return
	var caster_hero_id: String = String(caster.get_meta("hero_id", ""))
	var ability_id: String = ""
	match caster_hero_id:
		"Buffalo": ability_id = "BuffaloStampede"
		"Goose": ability_id = "GooseCover"
		"Fox": ability_id = "FoxSteal"
		_: return
	# Resolve via AbilityResolver — pure logic produces the effect dicts;
	# the host applies them and broadcasts the cast event so every peer
	# can play the visual.
	var effects: Array = AbilityResolverClass.resolve_help(ability_id, caster.position, target.position, _gather_enemy_refs())
	for effect in effects:
		_apply_help_effect(effect, caster, target)
	# Broadcast the cast so all peers see the visual flash.
	replication.rpc("_rpc_help_ability", caster_peer, target_peer, ability_id)
	if telemetry != null:
		telemetry.log("help_ability_cast", {
			"caster_peer": caster_peer,
			"target_peer": target_peer,
			"ability_id": ability_id,
		})

func _apply_help_effect(effect: Dictionary, caster: Node2D, target: Node2D) -> void:
	# Effects shape:
	#   { "kind": "line_charge", "from": Vector2, "to": Vector2,
	#     "width": float, "damage": float, "shield_seconds": float }
	#   { "kind": "buff_zone", "center_node": ref, "radius": float,
	#     "duration": float, "attack_speed_mult": float, "damage_resist": float }
	#   { "kind": "mark_target", "target_enemy": ref, "damage_mult": float, "yank_to": ref }
	var kind: String = String(effect.get("kind", ""))
	match kind:
		"line_charge":
			# Damage every enemy within `width` of the line from→to.
			var from: Vector2 = effect.from
			var to: Vector2 = effect.to
			var width: float = float(effect.width)
			var dmg: float = float(effect.damage)
			for n in _gather_enemy_refs():
				if _point_to_segment_distance(n.position, from, to) <= width:
					replication.host_apply_enemy_damage(n, dmg)
			# Teleport the caster to the line endpoint so Stampede reads
			# as a charge across the world rather than a stationary AoE.
			caster.position = to
			caster.current_tile = sector.world_to_tile(to)
		"buff_zone":
			# v1 implementation: mark a metadata flag on heroes inside
			# the radius for `duration` seconds. The visual flash is
			# the broadcast cast event; mechanical effect is currently
			# a no-op (M5 wires actual buffs into combat). Telemetry +
			# the visible cast still validate the spine.
			pass
		"mark_target":
			# v1 implementation: damage the marked enemy directly.
			var enemy_ref = effect.get("target_enemy")
			if enemy_ref != null and is_instance_valid(enemy_ref):
				replication.host_apply_enemy_damage(enemy_ref, float(effect.get("damage", 0.0)) * float(effect.get("damage_mult", 2.0)))
		_:
			pass

func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clamp((p - a).dot(ab) / max(ab.length_squared(), 0.001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)

# ── Signature abilities (Q) ────────────────────────────────────────────

func _try_fire_signature_ability() -> void:
	if hero == null or not is_instance_valid(hero) or bool(hero.get("is_downed")):
		return
	if GameState.signature_cooldown > 0.0:
		return
	var hero_id: String = String(hero.get_meta("hero_id", GameState.hero_id))
	var data: Dictionary = Heroes.ALL.get(hero_id, Heroes.Buffalo)
	var ability_id: String = String(data.get("signatureAbilityId", "BuffaloCharge"))
	var caster_pos: Vector2 = hero.position
	var target_pos: Vector2 = get_global_mouse_position()
	# Stamp cooldown locally so the HUD rail starts ticking immediately.
	# Host validates again and broadcasts the effect.
	var cd_max: float = float(data.get("signatureCooldown", 6.0))
	GameState.set_signature_cooldown(cd_max, cd_max)
	if MpIo.is_multiplayer() and not MpIo.is_host():
		# Client → host: route through replication. Host applies and
		# broadcasts a cast event so all peers see the visual.
		replication.rpc_id(1, "_rpc_request_signature", ability_id, caster_pos, target_pos)
		return
	# Host / solo: apply locally.
	_apply_signature_effects(MpIo.local_peer_id if MpIo.is_multiplayer() else 1, ability_id, caster_pos, target_pos)
	if MpIo.is_multiplayer():
		replication.rpc("_rpc_signature_visual", MpIo.local_peer_id, ability_id, caster_pos, target_pos)

func host_resolve_signature(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	if not MpIo.is_host():
		return
	_apply_signature_effects(caster_peer, ability_id, caster_pos, target_pos)
	replication.rpc("_rpc_signature_visual", caster_peer, ability_id, caster_pos, target_pos)

func _apply_signature_effects(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	var effects: Array = AbilityResolverClass.resolve(ability_id, caster_pos, target_pos)
	for effect in effects:
		_apply_signature_effect(effect, caster_peer)
	if telemetry != null:
		telemetry.log("ability_cast", {
			"ability_id": ability_id,
			"caster_peer": caster_peer,
		})

func _apply_signature_effect(effect: Dictionary, caster_peer: int) -> void:
	var kind: String = String(effect.get("kind", ""))
	var enemies: Array = _gather_enemy_refs()
	match kind:
		"damage_in_capsule":
			var from: Vector2 = effect.from
			var to: Vector2 = effect.to
			var width: float = float(effect.width)
			var dmg: float = float(effect.damage)
			for e in enemies:
				if _point_to_segment_distance(e.position, from, to) <= width:
					if MpIo.is_host():
						replication.host_apply_enemy_damage(e, dmg)
					else:
						e.damage(dmg)
			# Caster slides along the capsule path (Buffalo charge feel).
			var caster: Node2D = replication.hero_for_peer(caster_peer)
			if caster != null and is_instance_valid(caster):
				caster.position = to
				if sector != null:
					caster.current_tile = sector.world_to_tile(to)
		"damage_in_cone":
			var from: Vector2 = effect.from
			var dir: Vector2 = effect.direction
			var length: float = float(effect.length)
			var half_angle: float = float(effect.half_angle)
			var dmg: float = float(effect.damage)
			var cos_threshold: float = cos(half_angle)
			for e in enemies:
				var to_e: Vector2 = e.position - from
				var dist: float = to_e.length()
				if dist > length or dist < 0.0001:
					continue
				if to_e.normalized().dot(dir) < cos_threshold:
					continue
				if MpIo.is_host():
					replication.host_apply_enemy_damage(e, dmg)
				else:
					e.damage(dmg)
		"dash_and_strike":
			var to: Vector2 = effect.to
			var radius: float = float(effect.radius)
			var dmg: float = float(effect.damage)
			var caster: Node2D = replication.hero_for_peer(caster_peer)
			if caster != null and is_instance_valid(caster):
				caster.position = to
				if sector != null:
					caster.current_tile = sector.world_to_tile(to)
			for e in enemies:
				if (e.position - to).length() <= radius:
					if MpIo.is_host():
						replication.host_apply_enemy_damage(e, dmg)
					else:
						e.damage(dmg)
		_:
			pass

# ── Wave veiling (BUF-153) ─────────────────────────────────────────────

func _pick_first_hit_peer() -> int:
	# Choose the peer whose hero is closest to the rotating front. In
	# solo this collapses to the local hero. The default-front map per
	# hero gives a tie-break: heroes near their associated front are
	# preferred over heroes who happened to wander there — keeps the
	# spine readable across runs.
	var direction: String = MultiplayerDataClass.FRONT_ROTATION[_front_rotation_index]
	var heroes: Array = replication.all_heroes()
	if heroes.is_empty():
		return 0
	if heroes.size() == 1:
		return int(heroes[0].get_meta("peer_id", 0))
	var anchor_tile: Vector2i = _front_anchor_tile(direction)
	var best_pid: int = 0
	var best_score: float = INF
	for h in heroes:
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == 0 or bool(h.get("is_fallen")):
			continue
		var d: float = float(sector.tile_distance(h.current_tile, anchor_tile))
		# Bias: heroes whose default front matches direction get a small
		# discount so role-association reads even when positioning is
		# similar.
		var hero_id: String = String(h.get_meta("hero_id", ""))
		if MultiplayerDataClass.HERO_FRONT_DEFAULT.get(hero_id, "") == direction:
			d -= 1.5
		if d < best_score:
			best_score = d
			best_pid = pid
	return best_pid

func _front_anchor_tile(direction: String) -> Vector2i:
	# Anchor for "closeness to front" calculation. Picks a tile near the
	# edge in the chosen direction so heroes who've walked toward that
	# edge score lower distance and get picked.
	var grid: Vector2i = Sectors.TILE_GRID_SIZE
	match direction:
		"north": return Vector2i(grid.x / 2, 0)
		"south": return Vector2i(grid.x / 2, grid.y - 1)
		"east": return Vector2i(grid.x - 1, grid.y / 2)
		"west": return Vector2i(0, grid.y / 2)
		_: return Vector2i(grid.x / 2, grid.y - 1)

func _front_direction_for(idx: int) -> String:
	return String(MultiplayerDataClass.FRONT_ROTATION[idx % MultiplayerDataClass.FRONT_ROTATION.size()])

func apply_wave_state(first_hit_peer: int, composition: Dictionary) -> void:
	# Replication.gd routes the host's authoritative wave state here so
	# every peer (including the host, via call_local) lands on the same
	# _wave_first_hit_peer + composition. Banner + telemetry rendering
	# already happened in _on_wave_started; this is the host-truth
	# follow-up.
	_wave_first_hit_peer = first_hit_peer
	_wave_visible_to = [first_hit_peer] if first_hit_peer != 0 else []
	_veiled_composition = composition.duplicate(true)

func is_wave_visible_to_local() -> bool:
	# HUD reads this to decide between "show full composition" and
	# "show only in-combat veil". In solo, always visible.
	if not MpIo.is_multiplayer():
		return true
	if _wave_first_hit_peer == 0:
		return true
	return MpIo.local_peer_id in _wave_visible_to or MpIo.local_peer_id == _wave_first_hit_peer

func wave_first_hit_peer() -> int:
	return _wave_first_hit_peer

func wave_first_hit_hero_id() -> String:
	return MpIo.resolve_hero_for_peer(_wave_first_hit_peer)

func help_ability_cooldown_for(peer_id: int) -> float:
	return float(_help_ability_cooldowns.get(peer_id, 0.0))

func _recompute_first_hit_visibility() -> void:
	# Host-only: figure out which non-first-hit teammates have walked
	# within line-of-sight of the wave (using tile-distance proximity to
	# any spawning enemy). When a peer crosses the threshold, the host
	# broadcasts a "veil-lifted" RPC for that peer.
	if _wave_first_hit_peer == 0:
		return
	var enemies: Array = _gather_enemy_refs()
	if enemies.is_empty():
		return
	var newly_visible: Array = []
	for h in replication.all_heroes():
		if h == null or not is_instance_valid(h):
			continue
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == _wave_first_hit_peer:
			continue
		if pid in _wave_visible_to:
			continue
		# Threshold: any enemy within 6 tiles of this hero counts as LOS.
		var hero_tile: Vector2i = h.current_tile
		for e in enemies:
			if not is_instance_valid(e):
				continue
			if sector.tile_distance(hero_tile, e.current_tile) <= 6:
				newly_visible.append(pid)
				break
	for pid in newly_visible:
		_wave_visible_to.append(pid)
		# Re-broadcast the full composition to that peer so their HUD
		# can show what's coming. v1: HUD listens to the same wave_started
		# signal but reads `MpIo.last_wave_visible_to` to gate.
		MpIo.rpc("_rpc_peer_state", pid, "veil_lifted", "")

func _on_peer_state_changed(_peer_id: int, state_id: String, hero_id: String) -> void:
	# Surface seasonal-frame banner copy via the HUD. The HUD adapter
	# subscribes to MpIo.peer_state_changed too, so this is a side-channel
	# for telemetry + AI placeholder lifecycle.
	if telemetry != null:
		telemetry.log("peer_%s" % state_id, {"hero_id": hero_id})
	# AI placeholder: when a peer drops mid-run, flip their hero into
	# AI-placeholder mode so the world doesn't have a stationary corpse.
	# Reconnect lifts the AI flag.
	if state_id == MultiplayerDataClass.STATE_DROPPED:
		var dropped_hero: Node2D = replication.hero_for_peer(_peer_id)
		if dropped_hero != null and is_instance_valid(dropped_hero) and dropped_hero.has_method("set_ai_placeholder"):
			dropped_hero.set_ai_placeholder(true)
	elif state_id == MultiplayerDataClass.STATE_RECONNECTED or state_id == MultiplayerDataClass.STATE_CONNECTED:
		var back_hero: Node2D = replication.hero_for_peer(_peer_id)
		if back_hero != null and is_instance_valid(back_hero) and back_hero.has_method("set_ai_placeholder"):
			back_hero.set_ai_placeholder(false)
	elif state_id == MultiplayerDataClass.STATE_HOST_DROPPED:
		# Host went away — every client returns to the lobby (the run
		# can't continue without the source of truth). Defer the scene
		# change so any in-flight RPC handlers finish cleanly first.
		_return_to_lobby_after_host_drop.call_deferred()

func _return_to_lobby_after_host_drop() -> void:
	# Scene already changed? Bail so we don't double-navigate.
	if get_tree() == null or get_tree().current_scene == null:
		return
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
