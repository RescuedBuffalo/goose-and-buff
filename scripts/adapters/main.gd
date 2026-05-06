extends Node2D
##
## Boot + dispatch coordinator. Builds logic modules, wires adapters,
## delegates per-frame ticks, and forwards the public methods that
## replication.gd / hud_widget.gd reach into via has_method.
##
## After BUF-164 the heavy lifting lives in dedicated router children:
##   wave_veil          first-hit pick + composition veil + banner
##   revive_controller  downed / revive / help-cooldowns
##   combat_router      damage routing, projectiles, enemy lifecycle
##   ability_router     signature + help ability resolution
##   interaction_router gather / build / left-click swing dispatch
##   run_lifecycle      run state, start/victory/defeat, ember award

const Items := preload("res://data/items.gd")
const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const WorldGeneratorClass := preload("res://scripts/logic/world_generator.gd")
const DayNightCycleClass := preload("res://scripts/logic/day_night_cycle.gd")

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
const WaveVeilScript := preload("res://scripts/adapters/wave_veil.gd")
const ReviveControllerScript := preload("res://scripts/adapters/revive_controller.gd")
const CombatRouterScript := preload("res://scripts/adapters/combat_router.gd")
const AbilityRouterScript := preload("res://scripts/adapters/ability_router.gd")
const InteractionRouterScript := preload("res://scripts/adapters/interaction_router.gd")
const RunLifecycleScript := preload("res://scripts/adapters/run_lifecycle.gd")

const SectorScene := preload("res://scenes/sector.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")

const DEFAULT_HERO_ID := "Buffalo"

# Logic modules. Constructed once per run, reset between runs.
var day_night = null
var wave_director: WaveDirector = null
var inventory: InventorySystem = null
var combat: CombatSystem = null
var gather: GatherSystem = null
var build_logic: BuildSystem = null
var wave_gate = null
var telemetry: Telemetry = null

# Scene-tree adapter refs.
var sector
# `hero` always points at the *local* player's hero. In solo mode this
# is the only hero; in multiplayer it's the one this peer is driving.
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

# Routers (BUF-164).
var wave_veil = null
var revive_controller = null
var combat_router = null
var ability_router = null
var interaction_router = null
var run_lifecycle = null

# ── Boot ──────────────────────────────────────────────────────────────

func _ready() -> void:
	randomize()
	# Hero + seed come from GameState (set by the run-start screen via
	# BUF-145). Direct main.tscn launch with no run-start falls back to
	# defaults so the scene is still runnable for development.
	#
	# In multiplayer, MpIo.run_started broadcasts the host's seed +
	# hero assignments to every peer; GameState.set_run_config has
	# already been applied by the time we reach _ready, so reading from
	# GameState gives the same values on every machine.
	var hero_id: String = GameState.hero_id if not GameState.hero_id.is_empty() else DEFAULT_HERO_ID
	GameState.set_hero(hero_id)
	var run_seed: int = GameState.run_seed if GameState.run_seed != 0 else WorldGeneratorClass.random_seed()
	GameState.run_seed = run_seed
	_build_logic()
	_build_world()
	_build_ui()
	_build_routers()
	# run_lifecycle owns per-run state. Stamp seed + compute effective
	# stats BEFORE world build / hero spawn.
	run_lifecycle.run_seed = run_seed
	run_lifecycle.prepare(hero_id)
	_wire_signals()
	# World generation runs ONCE per run on day_index = 1. The chunks
	# stay constant across the run; the lighting adapter pushes the
	# cold-tint forward each successive night so the world *visibly*
	# deepens into winter (BUF-146). Determinism guarantee (BUF-151):
	# same seed produces identical world on every machine.
	run_lifecycle.generate_world(1)
	run_lifecycle.apply_stats_to_systems()
	run_lifecycle.start_run()

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
	# Replication is the multiplayer glue. The Replication node MUST be
	# named the same on every peer for NodePath-based RPC resolution.
	replication = ReplicationScript.new()
	replication.name = "Replication"
	add_child(replication)
	replication.attach(self, sector)
	replication.spawn_heroes_for_run()
	hero = replication.local_hero()
	# Camera enabled only on the local hero — remote puppets have their
	# camera node parented but disabled.
	if hero != null and hero.has_node("Camera"):
		(hero.get_node("Camera") as Camera2D).enabled = true
	combat_visuals = CombatVisualsScript.new()
	combat_visuals.name = "CombatVisuals"
	add_child(combat_visuals)
	build_overlay = BuildOverlayScript.new()
	build_overlay.name = "BuildOverlay"
	add_child(build_overlay)
	world_builder = WorldBuilderScript.new()
	world_builder.name = "WorldBuilder"
	add_child(world_builder)
	world_builder.attach(sector, self)
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
	debug_panel = DebugPanelScript.new()
	debug_panel.name = "DebugPanel"
	ui_layer.add_child(debug_panel)
	# Telemetry IO is non-visual — parent under self so its _process
	# tick fires and _exit_tree flushes on shutdown.
	telemetry_io = TelemetryIoScript.new()
	telemetry_io.name = "TelemetryIO"
	add_child(telemetry_io)
	telemetry_io.attach(telemetry)

func _build_routers() -> void:
	# Each router is a Node child so it can use get_tree() / RPC paths
	# consistently. Hero refs resolve on demand via a Callable so the
	# router survives respawns / puppet rebinds.
	var local_hero_provider := func(): return hero
	wave_veil = _add_router(WaveVeilScript, "WaveVeil")
	wave_veil.attach(sector, replication, hud, telemetry)
	revive_controller = _add_router(ReviveControllerScript, "ReviveController")
	revive_controller.attach(local_hero_provider, sector, replication, telemetry)
	combat_router = _add_router(CombatRouterScript, "CombatRouter")
	combat_router.attach(combat, inventory, replication, sector, telemetry, wave_director)
	ability_router = _add_router(AbilityRouterScript, "AbilityRouter")
	ability_router.attach(local_hero_provider, sector, replication, telemetry)
	interaction_router = _add_router(InteractionRouterScript, "InteractionRouter")
	interaction_router.attach({
		"sector": sector, "inventory": inventory, "combat": combat,
		"gather": gather, "build_logic": build_logic,
		"replication": replication, "telemetry": telemetry,
		"placement_parent": self, "local_hero_provider": local_hero_provider,
	})
	run_lifecycle = _add_router(RunLifecycleScript, "RunLifecycle")
	run_lifecycle.attach({
		"sector": sector, "hero": hero, "hud": hud,
		"end_screen": end_screen, "inventory_hud": inventory_hud,
		"inventory": inventory, "combat": combat, "gather": gather,
		"wave_director": wave_director, "day_night": day_night,
		"telemetry": telemetry, "replication": replication,
		"world_builder": world_builder, "debug_overlay": debug_overlay,
		"debug_panel": debug_panel, "wave_veil": wave_veil,
		"revive_controller": revive_controller,
	})

func _add_router(script: Resource, node_name: String) -> Node:
	var n: Node = script.new()
	n.name = node_name
	add_child(n)
	return n

func _wire_signals() -> void:
	hud.bind(day_night)
	inventory_hud.bind(inventory)
	build_overlay.attach(sector, inventory, build_logic)
	combat_visuals.attach(combat)
	lighting.bind(day_night)
	wave_gate.bind(day_night, wave_director)
	# Wave start → veil router; spawn / wave-end → combat router.
	wave_director.wave_started.connect(wave_veil.on_wave_started)
	wave_director.enemy_due.connect(combat_router.on_enemy_due)
	wave_director.wave_ended.connect(combat_router.on_wave_ended)
	wave_director.wave_ended.connect(run_lifecycle.on_wave_ended)
	# Combat / interaction routers feed run_lifecycle's counters.
	combat_router.enemy_killed.connect(run_lifecycle.on_enemy_killed)
	interaction_router.resources_gathered.connect(run_lifecycle.add_resources_gathered)
	build_overlay.place_requested.connect(interaction_router.on_place_requested)
	day_night.phase_changed.connect(run_lifecycle.on_phase_changed)
	day_night.cycle_complete.connect(run_lifecycle.on_cycle_complete)
	sector.core_destroyed.connect(run_lifecycle.on_core_destroyed)
	# Defeat in solo = local hero downed. Multiplayer doesn't end on a
	# single hero going down — the run ends only when the lodge falls
	# or every hero is fallen at once.
	for h in replication.all_heroes():
		var pid: int = int(h.get_meta("peer_id", 0))
		h.hero_downed.connect(run_lifecycle.on_hero_downed.bind(pid))
		h.hero_fallen.connect(run_lifecycle.on_hero_fallen.bind(pid))
	end_screen.restart_requested.connect(run_lifecycle.on_restart_requested)
	end_screen.player_engaged.connect(run_lifecycle.cancel_run_end_transition)
	# Multiplayer-only wiring: peer connection events for the seasonal-
	# frame banner copy + AI placeholder lifecycle (BUF-155).
	if MpIo.is_multiplayer():
		MpIo.peer_state_changed.connect(_on_peer_state_changed)

# ── Frame loop ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# When the run is over, freeze ticks so the end-screen scrim doesn't
	# sit on top of a noisy world.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	# Logic ticks. In multiplayer, day_night + wave_director are still
	# *driven* on every peer to keep visible UI in sync — they're pure
	# functions of (start time, dt) given the same starting seed and
	# tick cadence. The host alone owns enemy spawning.
	day_night.tick(delta)
	wave_director.tick(delta)
	combat.tick(delta)
	if replication != null:
		replication.tick_position_sync(delta)
	if revive_controller != null:
		revive_controller.tick(delta)
	if gather.is_active() and is_instance_valid(hero):
		var node = gather.active_node()
		if node != null and is_instance_valid(node):
			gather.tick(delta, hero.current_tile, node.current_tile, inventory.equipped_weapon())
	if Input.is_action_pressed("gather"):
		interaction_router.try_start_gather()
	elif Input.is_action_just_released("gather"):
		gather.cancel_active()
	# Hotbar bindings (1..8). Slots 9+ from the Extra-pouch upgrade are
	# storage-only — clickable on the HUD but not hotkey-addressable.
	for i in min(8, inventory.slot_count):
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			inventory.select_slot(i)
	# Q fires the hero's signature ability. Cooldown ticked here so the
	# HUD rail has live feedback.
	if GameState.signature_cooldown > 0.0:
		GameState.set_signature_cooldown(max(0.0, GameState.signature_cooldown - delta), GameState.signature_cooldown_max)
	if Input.is_action_just_pressed("signature_ability"):
		ability_router.try_fire_signature_ability()
	# Host-only: lift veil for teammates within LOS of the wave (BUF-153).
	if MpIo.is_host() or not MpIo.is_multiplayer():
		wave_veil.tick_visibility()

func _unhandled_input(event: InputEvent) -> void:
	# F3 toggles the debug overlay. F4 dumps WorldDef to user://debug/.
	# Captured here rather than as a registered input action so we don't
	# have to touch project.godot for dev-only toggles.
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_F3:
			if debug_overlay != null:
				debug_overlay.toggle()
			if debug_panel != null:
				debug_panel.toggle()
			return
		if k.pressed and k.keycode == KEY_F4:
			if debug_overlay != null and run_lifecycle != null:
				debug_overlay.dump_world(run_lifecycle.run_seed)
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
	# Help-ability targeting (BUF-154). Held E + click on a teammate
	# (or their portrait) fires the help ability instead of swinging.
	if Input.is_action_pressed("help_ability"):
		var target_peer: int = revive_controller.help_target_peer_at(get_global_mouse_position(), wave_veil.wave_first_hit_peer())
		if target_peer != 0:
			revive_controller.request_help_ability(target_peer)
			return
	var sel_id: String = inventory.selected_item_id()
	if not sel_id.is_empty() and Items.is_placeable(sel_id):
		# Build overlay owns left-click while a placeable is armed.
		return
	interaction_router.handle_swing_click()

# ── Multiplayer peer-state plumbing ──────────────────────────────────

func _on_peer_state_changed(peer_id: int, state_id: String, hero_id: String) -> void:
	# Surface seasonal-frame banner copy via the HUD. The HUD adapter
	# subscribes to MpIo.peer_state_changed too, so this is a side-channel
	# for telemetry + AI placeholder lifecycle.
	if telemetry != null:
		telemetry.log("peer_%s" % state_id, {"hero_id": hero_id})
	if state_id == MultiplayerDataClass.STATE_DROPPED:
		var dropped_hero: Node2D = replication.hero_for_peer(peer_id)
		if dropped_hero != null and is_instance_valid(dropped_hero) and dropped_hero.has_method("set_ai_placeholder"):
			dropped_hero.set_ai_placeholder(true)
	elif state_id == MultiplayerDataClass.STATE_RECONNECTED or state_id == MultiplayerDataClass.STATE_CONNECTED:
		var back_hero: Node2D = replication.hero_for_peer(peer_id)
		if back_hero != null and is_instance_valid(back_hero) and back_hero.has_method("set_ai_placeholder"):
			back_hero.set_ai_placeholder(false)
	elif state_id == MultiplayerDataClass.STATE_HOST_DROPPED:
		# Host went away — every client returns to the lobby. Defer the
		# scene change so any in-flight RPC handlers finish cleanly.
		_return_to_lobby_after_host_drop.call_deferred()

func _return_to_lobby_after_host_drop() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

# ── Public forwarders (called by replication.gd via has_method) ──────
##
## These keep the contract that replication.gd expects on its
## `main_node` reference. Each delegates to the router that owns the
## logic. HUD also calls wave_first_hit_peer() via `_main_ref`.

func apply_wave_state(first_hit_peer: int, composition: Dictionary) -> void:
	wave_veil.apply_wave_state(first_hit_peer, composition)

func is_wave_visible_to_local() -> bool:
	return wave_veil.is_wave_visible_to_local()

func wave_first_hit_peer() -> int:
	return wave_veil.wave_first_hit_peer()

func wave_first_hit_hero_id() -> String:
	return wave_veil.wave_first_hit_hero_id()

func help_ability_cooldown_for(peer_id: int) -> float:
	return revive_controller.help_ability_cooldown_for(peer_id)

func host_resolve_remote_swing(peer_id: int, weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int) -> void:
	combat_router.host_resolve_remote_swing(peer_id, weapon_id, origin, facing, ammo_count)

func host_resolve_revive(caster_peer: int, target_peer: int) -> void:
	revive_controller.host_resolve_revive(caster_peer, target_peer)

func host_resolve_help_ability(caster_peer: int, target_peer: int) -> void:
	ability_router.host_resolve_help_ability(caster_peer, target_peer)

func host_resolve_signature(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	ability_router.host_resolve_signature(caster_peer, ability_id, caster_pos, target_pos)

func _apply_signature_effects(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	# replication.gd's _rpc_signature_visual checks for this method;
	# kept on main as a forwarder so the contract surface doesn't shift.
	# Visual replay on remote clients is currently a no-op (BUF-172).
	ability_router.apply_signature_effects(caster_peer, ability_id, caster_pos, target_pos)
