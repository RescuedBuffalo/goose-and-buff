extends Node
##
## World interaction router (BUF-164). Owns gather start/progress/
## complete plumbing, build placement plumbing, and the left-click
## swing dispatch (melee + ranged client intent). Split out of main.gd
## so the boot script doesn't carry input behavior alongside wiring.
##
## Public surface used by main.gd:
##   attach(refs)               — bag of system refs
##   try_start_gather()         — called each frame when the gather key
##                                is held
##   handle_swing_click()       — left-click resolution
##   on_place_requested(item, tile)
##
## Signals:
##   resources_gathered(amount: int)  — main forwards to run_lifecycle
##                                      counter
##
## Refs come in via attach so the router has no peeking at scene-tree
## globals. The Items + Weapons data tables are stable preloads.

const Items := preload("res://data/items.gd")
const Weapons := preload("res://data/weapons.gd")
const Sectors := preload("res://data/sectors.gd")
const PlaceableScene := preload("res://scenes/placeable.tscn")

signal resources_gathered(amount: int)

var sector = null
var inventory: InventorySystem = null
var combat: CombatSystem = null
var gather: GatherSystem = null
var build_logic: BuildSystem = null
var replication = null
var telemetry: Telemetry = null
# Owner of the spawned placeables (parent node). Main usually = self.
var placement_parent: Node = null
var _local_hero_provider: Callable = Callable()
# Returns the local effective_stats dict so swing-click can pass the
# client's attack_speed mult to the host. Held as a Callable so the
# router doesn't pin a stale ref across run-start (PR #43 review).
var _effective_stats_provider: Callable = Callable()

func attach(refs: Dictionary) -> void:
	sector = refs.get("sector")
	inventory = refs.get("inventory")
	combat = refs.get("combat")
	gather = refs.get("gather")
	build_logic = refs.get("build_logic")
	replication = refs.get("replication")
	telemetry = refs.get("telemetry")
	placement_parent = refs.get("placement_parent")
	_local_hero_provider = refs.get("local_hero_provider", Callable())
	_effective_stats_provider = refs.get("effective_stats_provider", Callable())
	# Wire signals from logic systems through this router.
	gather.gather_progress.connect(_on_gather_progress)
	gather.gather_completed.connect(_on_gather_completed)
	gather.gather_cancelled.connect(_on_gather_cancelled)
	build_logic.placed.connect(_on_placed)

# ── Gather ────────────────────────────────────────────────────────────

func try_start_gather() -> void:
	var hero: Node2D = _resolve_local_hero()
	if hero == null or hero.is_downed:
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
	# tree/rock visually reads as untouched again.
	if node_ref != null and is_instance_valid(node_ref) and node_ref.has_method("clear_progress"):
		node_ref.clear_progress()

func _on_gather_completed(node_ref, yields: Dictionary) -> void:
	var resource_kind: String = ""
	if node_ref != null and is_instance_valid(node_ref) and node_ref.has_method("resource_kind_id"):
		resource_kind = String(node_ref.resource_kind_id())
	for item_id in yields:
		var leftover: int = inventory.add(item_id, int(yields[item_id]))
		var added: int = int(yields[item_id]) - leftover
		if added > 0:
			resources_gathered.emit(added)
		if leftover > 0:
			# BUF-176 will replace this with an in-world drop.
			push_warning("Inventory full — %d %s left on the floor" % [leftover, item_id])
	if telemetry != null:
		telemetry.log("resource_gathered", {
			"resource_kind": resource_kind,
			"yields": yields.duplicate(),
		})
	if node_ref != null and is_instance_valid(node_ref):
		node_ref.deplete()

# ── Build ─────────────────────────────────────────────────────────────

func on_place_requested(item_id: String, tile: Vector2i) -> void:
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
	if placement_parent != null:
		placement_parent.add_child(p)
	else:
		add_child(p)
	p.place_at_tile(tile)
	if not inventory.has_at_least(item_id, 1):
		sector.clear_build_ghost()

# ── Left-click swing dispatch ─────────────────────────────────────────

func handle_swing_click() -> void:
	var hero: Node2D = _resolve_local_hero()
	if hero == null or hero.is_downed:
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
		for slot in inventory.slots:
			if String(slot.get("item_id", "")) == ammo_id:
				ammo_count += int(slot.get("count", 0))
	# Multiplayer client: send swing intent to host, who re-runs the
	# resolver and broadcasts damage_dealt back. Local hero gets a
	# swing arc immediately from the local combat.swing_started emit —
	# that's purely visual; damage application happens off the broadcast.
	if MpIo.is_multiplayer() and not MpIo.is_host():
		# Cooldown gate (PR #41 review follow-up). Without can_swing()
		# here, a client could spam click events faster than the weapon
		# allows — the host's resolver runs in a per-peer CombatSystem
		# (combat_router.host_resolve_remote_swing) so it never rejects
		# on the client's behalf. note_swing_cooldown after the emit
		# stamps the same cooldown the host's resolver will, so client
		# and host stay in lockstep without an extra round trip.
		if not combat.can_swing():
			return
		var weapon: Dictionary = Weapons.get_weapon(equipped)
		var dir: Vector2 = hero.facing.normalized() if hero.facing.length_squared() > 0.0001 else Vector2.RIGHT
		var range_tiles: float = float(weapon.range_tiles)
		var length_px: float = range_tiles * 35.0
		var half_angle_rad: float = deg_to_rad(float(weapon.arc_degrees) * 0.5)
		# Ranged: deduct one arrow from the local inventory before
		# firing. The host doesn't touch the swinger's inventory —
		# clients deduct locally so trigger-mash doesn't spawn
		# projectiles the resolver will reject.
		if Weapons.is_ranged(equipped):
			if ammo_count < 1:
				return
			var ammo_id: String = Weapons.ammo_for(equipped)
			if not ammo_id.is_empty():
				inventory.remove_item(ammo_id, 1)
		combat.swing_started.emit(equipped, hero.position, dir, length_px, half_angle_rad)
		combat.note_swing_cooldown(equipped)
		# Pass the client's effective attack_speed mult so the host's
		# per-peer cooldown gate matches the client's faster cadence
		# when upgrades are owned. Without this, an upgraded client's
		# legitimate swings would be rejected and bow shots would waste
		# their already-deducted arrow (PR #43 review).
		var stats: Dictionary = _resolve_effective_stats()
		var client_attack_speed: float = float(stats.get("attack_speed", 1.0))
		replication.client_request_swing(equipped, hero.position, hero.facing, ammo_count, client_attack_speed)
		return
	var swing_result: Dictionary = combat.resolve_swing(hero.position, hero.facing, equipped, enemies, ammo_count)
	if telemetry != null and swing_result.get("ok", false):
		telemetry.log("ability_cast", {
			"ability_id": "weapon_swing",
			"weapon_id": String(swing_result.get("weapon", "")),
			"hits": int((swing_result.get("hits", []) as Array).size()),
			"ranged": bool(swing_result.get("ranged", false)),
		})

# ── helpers ──────────────────────────────────────────────────────────

func _resolve_local_hero() -> Node2D:
	if _local_hero_provider.is_null():
		return null
	var ref = _local_hero_provider.call()
	if ref == null or not is_instance_valid(ref):
		return null
	return ref as Node2D

func _resolve_effective_stats() -> Dictionary:
	if _effective_stats_provider.is_null():
		return {}
	var ref = _effective_stats_provider.call()
	if typeof(ref) != TYPE_DICTIONARY:
		return {}
	return ref
