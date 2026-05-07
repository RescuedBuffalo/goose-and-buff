extends Node
##
## Run lifecycle coordinator (BUF-164). Owns per-run state +
## start/victory/defeat transitions. Split out of main.gd so the boot
## script stays focused on wiring.
##
## Per-run state lives here:
##   run_seed, world_def, effective_stats, starter_items
##   resources_gathered, enemies_felled, nights_survived
##   embers_awarded_this_run
##   _run_started_msec, _run_end_auto_transition_cancelled
##
## Public surface used by main.gd:
##   prepare(hero_id)        — compute effective_stats + starter_items
##   generate_world(day_index)
##   apply_stats_to_systems()
##   start_run()
##   add_resources_gathered(n) / on_enemy_killed() / on_wave_ended(round_index)
##   on_phase_changed(phase, day_index)
##   on_cycle_complete(nights)
##   on_hero_downed(peer_id) / on_hero_fallen(peer_id)
##   on_core_destroyed()
##   on_restart_requested() / cancel_run_end_transition()

const Sectors := preload("res://data/sectors.gd")
const DayNight := preload("res://data/day_night.gd")
const RunEconomy := preload("res://data/run_economy.gd")
const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const DayNightCycleClass := preload("res://scripts/logic/day_night_cycle.gd")
const StatSystemClass := preload("res://scripts/logic/stat_system.gd")
const WorldGeneratorClass := preload("res://scripts/logic/world_generator.gd")
const SaveStateClass := preload("res://scripts/logic/save_state.gd")

const LODGE_SCENE_PATH := "res://scenes/lodge/lodge.tscn"
# Pause before the scene swap so the player sees what just happened.
# Bumped from 1.6s so the Copy-seed button (BUF-145) is reachable.
const RUN_END_TO_LODGE_DELAY_SECONDS := 6.0
const DEFAULT_HERO_ID := "Buffalo"

# Run state aggregates.
var run_seed: int = 0
var world_def: Dictionary = {}
var effective_stats: Dictionary = {}
var starter_items: Array = []
var resources_gathered: int = 0
var enemies_felled: int = 0
var nights_survived: int = 0
var embers_awarded_this_run: int = 0
var _run_started_msec: int = 0
var _run_end_auto_transition_cancelled: bool = false

# Adapter refs supplied via attach().
var sector = null
var hero = null
var hud = null
var end_screen = null
var inventory_hud = null
var inventory: InventorySystem = null
var combat: CombatSystem = null
var gather: GatherSystem = null
var wave_director: WaveDirector = null
var day_night = null
var telemetry: Telemetry = null
var replication = null
var world_builder = null
var debug_overlay = null
var debug_panel = null
# Routers we need to reset / coordinate with on run-start.
var wave_veil = null
var revive_controller = null

func attach(refs: Dictionary) -> void:
	sector = refs.get("sector")
	hero = refs.get("hero")
	hud = refs.get("hud")
	end_screen = refs.get("end_screen")
	inventory_hud = refs.get("inventory_hud")
	inventory = refs.get("inventory")
	combat = refs.get("combat")
	gather = refs.get("gather")
	wave_director = refs.get("wave_director")
	day_night = refs.get("day_night")
	telemetry = refs.get("telemetry")
	replication = refs.get("replication")
	world_builder = refs.get("world_builder")
	debug_overlay = refs.get("debug_overlay")
	debug_panel = refs.get("debug_panel")
	wave_veil = refs.get("wave_veil")
	revive_controller = refs.get("revive_controller")

# ── Pre-run wiring (BUF-147) ──────────────────────────────────────────

func prepare(hero_id: String) -> void:
	# Compute effective stats + starter items from owned upgrades. Run
	# this BEFORE world build / hero spawn — main reads effective_stats
	# to size the lodge core, set HP, etc.
	effective_stats = StatSystemClass.effective_stats(hero_id, SaveIo.owned_upgrades())
	starter_items = _build_starter_items()

func _build_starter_items() -> Array:
	# Pick the best axe the player has unlocked at the lodge.
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
	if unlocks.has("spear"):
		items.append({"id": "spear", "count": 1})
	if unlocks.has("bow"):
		items.append({"id": "bow", "count": 1})
	if unlocks.has("arrow"):
		items.append({"id": "arrow", "count": 12})
	return items

# ── World generation (BUF-144) ───────────────────────────────────────

func generate_world(day_index: int) -> void:
	var t0: int = Time.get_ticks_msec()
	world_def = WorldGeneratorClass.generate(run_seed, day_index, GameState.hero_id)
	var elapsed: int = Time.get_ticks_msec() - t0
	if elapsed > 250:
		push_warning("WorldGenerator slow: %d ms (target <250)" % elapsed)
	if sector != null and sector.has_method("adopt_world"):
		sector.adopt_world(world_def)
	if world_builder != null:
		world_builder.build_from(world_def)
	if debug_overlay != null:
		debug_overlay.set_world(world_def)
	if debug_panel != null:
		debug_panel.set_world(world_def)

func apply_stats_to_systems() -> void:
	# Stat dispatch (BUF-147). Each consumer reads what it cares about
	# from the effective_stats dict. Per-peer combat-stat propagation
	# tracked under BUF-169.
	var stats: Dictionary = effective_stats
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
	# Apply inventory_slots BEFORE start_run → inventory.reset() so the
	# slots array is built at the new size.
	if inventory != null:
		inventory.set_slot_count(int(stats.inventory_slots))
	GameState.set_signature_cooldown(0.0, float(stats.ability_cooldown))

func start_run() -> void:
	# Snapshot identity before reset() so the same hero + seed survive
	# the phase / hp wipe that GameState.reset() applies.
	var preserved_hero: String = GameState.hero_id if not GameState.hero_id.is_empty() else DEFAULT_HERO_ID
	GameState.reset()
	GameState.set_hero(preserved_hero)
	GameState.run_seed = run_seed
	# Re-stamp ability cooldown AFTER reset() (which clears it).
	GameState.set_signature_cooldown(0.0, float(effective_stats.get("ability_cooldown", 0.0)))
	sector.set_hero(GameState.hero_id)
	sector.reset_core(float(effective_stats.get("lodge_hp_max", Sectors.CORE_HEALTH)))
	hero.reset_hp()
	hero.reset_position()
	wave_director.reset()
	# Seed wave_director so every peer rolls the same archetype on
	# round 2 (BUF-151 determinism).
	wave_director.set_seed(run_seed)
	day_night.reset()
	inventory.reset()
	combat.reset()
	combat.set_stat_modifiers(
		float(effective_stats.get("attack_damage", 1.0)),
		float(effective_stats.get("attack_speed", 1.0)),
		float(effective_stats.get("attack_range", 0.0)),
	)
	gather.reset()
	gather.set_speed_multiplier(float(effective_stats.get("gather_speed", 1.0)))
	telemetry.reset()
	if wave_veil != null:
		wave_veil.reset()
	if revive_controller != null:
		revive_controller.reset()
	resources_gathered = 0
	enemies_felled = 0
	nights_survived = 0
	embers_awarded_this_run = 0
	_run_started_msec = Time.get_ticks_msec()
	for item in starter_items:
		inventory.add(item.id, int(item.count))
	inventory.select_slot(0)
	end_screen.visible = false
	hud.visible = true
	inventory_hud.visible = true
	telemetry.start_run({
		"hero_id": GameState.hero_id,
		"max_nights": DayNight.MAX_NIGHTS,
		"deck_composition": starter_items.duplicate(true),
		"seed": run_seed,
		"seed_string": WorldGeneratorClass.seed_to_string(run_seed),
		"owned_upgrades": SaveIo.owned_upgrades().duplicate(),
	})

# ── Counters ──────────────────────────────────────────────────────────

func add_resources_gathered(n: int) -> void:
	resources_gathered += n

func on_enemy_killed(_enemy_type: String) -> void:
	enemies_felled += 1

func on_wave_ended(round_index: int) -> void:
	nights_survived += 1
	if telemetry != null:
		# Schema (docs/telemetry-events.md): wave_end carries the
		# cumulative nights_survived count after this wave.
		telemetry.log("wave_end", {
			"round_index": round_index,
			"nights_survived": nights_survived,
		})

# ── Day/night, hero state, run-end ────────────────────────────────────

func on_phase_changed(phase: int, _day_index: int) -> void:
	# Dawn respawn for fallen heroes (BUF-152).
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
		var spawn_world: Vector2 = sector.tile_to_world(Sectors.SPAWN_TILE)
		h.position = spawn_world
		h.current_tile = Sectors.SPAWN_TILE
		replication.host_mark_hero_revived(pid, MultiplayerDataClass.FALLEN_RESPAWN_HP_RATIO)
		if telemetry != null:
			telemetry.log("hero_dawn_respawn", {"peer_id": pid})

func on_cycle_complete(nights: int) -> void:
	_run_victory.call_deferred(nights)

func on_hero_downed(peer_id: int) -> void:
	# Solo: a downed local hero ends the run immediately (M2 contract).
	# Multiplayer: a single downed hero starts a 30s revive timer; the
	# run only ends when every hero is fallen at once or the lodge falls.
	if telemetry != null:
		telemetry.log("hero_downed", {"peer_id": peer_id})
	if not MpIo.is_multiplayer():
		_run_defeat.call_deferred()

func on_hero_fallen(peer_id: int) -> void:
	if telemetry != null:
		telemetry.log("hero_fallen", {"peer_id": peer_id})
	if MpIo.is_multiplayer() and _every_hero_fallen():
		_run_defeat.call_deferred()

func _every_hero_fallen() -> bool:
	for h in replication.all_heroes():
		if not bool(h.get("is_fallen")):
			return false
	return true

func on_core_destroyed() -> void:
	_run_defeat.call_deferred()

func _run_victory(nights: int) -> void:
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	end_screen.set_stats(nights_survived, resources_gathered, enemies_felled)
	end_screen.set_seed(run_seed)
	_award_embers(SaveStateClass.OUTCOME_VICTORY)
	end_screen.set_embers_earned(embers_awarded_this_run)
	end_screen.show_victory()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "victory",
			"nights_survived": nights,
			"resources_gathered": resources_gathered,
			"enemies_felled": enemies_felled,
			"embers_earned": embers_awarded_this_run,
		})
	_record_run_and_go_to_lodge(SaveStateClass.OUTCOME_VICTORY)

func _run_defeat() -> void:
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	end_screen.set_stats(nights_survived, resources_gathered, enemies_felled)
	end_screen.set_seed(run_seed)
	_award_embers(SaveStateClass.OUTCOME_DEFEAT)
	end_screen.set_embers_earned(embers_awarded_this_run)
	end_screen.show_defeat()
	if telemetry != null:
		telemetry.end_run({
			"outcome": "defeat",
			"nights_survived": nights_survived,
			"resources_gathered": resources_gathered,
			"enemies_felled": enemies_felled,
			"embers_earned": embers_awarded_this_run,
		})
	_record_run_and_go_to_lodge(SaveStateClass.OUTCOME_DEFEAT)

func _award_embers(outcome: String) -> void:
	# Single-shot per run. Call only from victory/defeat paths.
	var amount: int = RunEconomy.award_for_run(outcome, nights_survived, resources_gathered, enemies_felled)
	embers_awarded_this_run = amount
	if amount > 0:
		SaveIo.add_embers(amount)
	if telemetry != null:
		telemetry.log("ember_earned", {
			"outcome": outcome,
			"amount": amount,
			"nights_survived": nights_survived,
			"resources_gathered": resources_gathered,
			"enemies_felled": enemies_felled,
		})

func _record_run_and_go_to_lodge(outcome: String) -> void:
	var duration: float = float(Time.get_ticks_msec() - _run_started_msec) / 1000.0
	SaveIo.record_run(
		GameState.hero_id,
		outcome,
		nights_survived,
		resources_gathered,
		enemies_felled,
		duration,
		run_seed,
	)
	# Auto-transition reads _run_end_auto_transition_cancelled so the
	# end-screen Copy button can stop it. SceneTreeTimer can't be
	# unregistered, so we use a flag.
	_run_end_auto_transition_cancelled = false
	get_tree().create_timer(RUN_END_TO_LODGE_DELAY_SECONDS).timeout.connect(_auto_transition_to_lodge)

func cancel_run_end_transition() -> void:
	_run_end_auto_transition_cancelled = true

func _auto_transition_to_lodge() -> void:
	if _run_end_auto_transition_cancelled:
		return
	get_tree().change_scene_to_file(LODGE_SCENE_PATH)

func on_restart_requested() -> void:
	get_tree().change_scene_to_file(LODGE_SCENE_PATH)
