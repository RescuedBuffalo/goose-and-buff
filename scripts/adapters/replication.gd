extends Node
##
## Replication adapter (BUF-151 + BUF-152). Owns the @rpc surface that
## bridges local logic (CombatSystem, AbilityResolver, hero positions,
## enemy spawns) to the MultiplayerAPI. Lives as a child of Main so its
## NodePath ("/root/Main/Replication") is identical on every peer — the
## MultiplayerAPI uses NodePath equality to resolve RPCs.
##
## Architecture rules: this script is the *only* place RPC traffic lives
## for the gameplay scene. Pure logic (CombatSystem etc) doesn't know it
## is being networked. Main connects logic signals to this adapter; this
## adapter forwards them as RPCs and applies inbound RPCs back to logic.
##
## Solo mode: when MpIo.is_multiplayer() is false, every helper is a
## no-op or a direct local call so single-player still works without
## any networking concerns.

const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Enemies := preload("res://data/enemies.gd")
const Waves := preload("res://data/waves.gd")
const HeroScene := preload("res://scenes/hero.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")

signal hero_spawned(peer_id: int, hero_id: String, hero_node: Node2D, is_local: bool)
signal enemy_spawned(network_id: int, enemy_type: String, enemy_node: Node2D)
signal enemy_removed(network_id: int)
signal damage_to_enemy(network_id: int, amount: float)
signal damage_to_hero(peer_id: int, amount: float)
signal hero_revived(peer_id: int)
signal hero_fallen(peer_id: int)
signal help_ability_cast(caster_peer: int, target_peer: int, ability_id: String)

var main_node: Node2D = null
var sector_node: Node = null
# peer_id (int) → Hero node ref
var heroes_by_peer: Dictionary = {}
# network_id (int) → Enemy node ref. Host assigns ids as it spawns.
var enemies_by_id: Dictionary = {}
var _next_enemy_id: int = 1
# Per-peer position cache so the host can rebroadcast inbound moves
# without holding pointers across frames.
var _pending_positions: Dictionary = {}
# Per-peer downed timer accumulator. Host-only — clients receive state
# transitions via RPC.
var _downed_timers: Dictionary = {}
var _position_sync_accum: float = 0.0

func attach(main: Node2D, sector: Node) -> void:
	main_node = main
	sector_node = sector

# ── Hero spawn lifecycle ────────────────────────────────────────────────

func spawn_heroes_for_run() -> void:
	# Called once at run-start by main.gd. In multiplayer, spawn one hero
	# per peer with their assigned hero_id; in solo, spawn just the local
	# hero. The local hero's input authority is the peer that owns it;
	# remote heroes are puppets that linearly interpolate toward their
	# last received position.
	if not MpIo.is_multiplayer():
		_spawn_hero_for_peer(1, GameState.hero_id, true)
		return
	var assignments: Dictionary = MpIo.hero_assignments
	for peer_id_v in assignments.keys():
		var pid: int = int(peer_id_v)
		var hero_id: String = String(assignments[pid])
		var is_local: bool = pid == MpIo.local_peer_id
		_spawn_hero_for_peer(pid, hero_id, is_local)

func _spawn_hero_for_peer(peer_id: int, hero_id: String, is_local: bool) -> Node2D:
	var hero: Node2D = HeroScene.instantiate()
	hero.set_hero(hero_id)
	hero.attach_sector(sector_node)
	hero.set_meta("peer_id", peer_id)
	hero.set_meta("is_local_hero", is_local)
	hero.set_meta("hero_id", hero_id)
	main_node.add_child(hero)
	# Stamp the puppet flag *after* add_child so Hero._ready has already
	# wired the @onready camera ref. Without this, every remote hero
	# kept reading the local keyboard each frame until the first network
	# pose update arrived — and on the host, that also mutated the
	# authoritative current_tile that revive/visibility/enemy-target
	# checks consult, so a player walking around their machine could
	# yank a teammate's hero around the world.
	if hero.has_method("set_remote_puppet"):
		hero.set_remote_puppet(not is_local)
	heroes_by_peer[peer_id] = hero
	hero_spawned.emit(peer_id, hero_id, hero, is_local)
	return hero

func local_hero() -> Node2D:
	return heroes_by_peer.get(MpIo.local_peer_id, null) if MpIo.is_multiplayer() else heroes_by_peer.get(1, null)

func hero_for_peer(peer_id: int) -> Node2D:
	return heroes_by_peer.get(peer_id, null)

func all_heroes() -> Array:
	var out: Array = []
	for v in heroes_by_peer.values():
		if v != null and is_instance_valid(v):
			out.append(v)
	return out

# ── Enemy spawn (host-only entry) ──────────────────────────────────────

func host_spawn_enemy(enemy_type: String, slot_index: int, stat_scale: Dictionary) -> Node2D:
	# Called by the wave-director-driven spawn callback on the host. Picks
	# a network id, creates the enemy locally, and broadcasts the spawn
	# to clients so they create matching puppets.
	if MpIo.is_multiplayer() and not MpIo.is_host():
		return null
	var nid: int = _allocate_enemy_id()
	var entry_tiles: Array[Vector2i] = Sectors.ENEMY_ENTRY_TILES
	var entry_tile: Vector2i = entry_tiles[slot_index % entry_tiles.size()]
	var enemy: Node2D = _spawn_enemy_local(nid, enemy_type, entry_tile, stat_scale)
	if MpIo.is_multiplayer():
		rpc("_rpc_spawn_enemy", nid, enemy_type, entry_tile, stat_scale)
	return enemy

func _spawn_enemy_local(nid: int, enemy_type: String, tile: Vector2i, stat_scale: Dictionary) -> Node2D:
	var enemy: Node2D = EnemyScene.instantiate()
	enemy.configure(enemy_type, stat_scale)
	enemy.attach_sector(sector_node)
	enemy.set_meta("network_id", nid)
	# Host owns enemy AI; clients run them as puppets — gate _physics_process
	# on the enemy adapter via this meta flag.
	enemy.set_meta("is_puppet", MpIo.is_multiplayer() and not MpIo.is_host())
	main_node.add_child(enemy)
	enemy.place_at_tile(tile)
	enemies_by_id[nid] = enemy
	enemy_spawned.emit(nid, enemy_type, enemy)
	return enemy

func _allocate_enemy_id() -> int:
	var nid: int = _next_enemy_id
	_next_enemy_id += 1
	return nid

# ── Hero position sync ──────────────────────────────────────────────────

func tick_position_sync(delta: float) -> void:
	if not MpIo.is_multiplayer():
		return
	_position_sync_accum += delta
	if _position_sync_accum < MultiplayerDataClass.POSITION_SYNC_INTERVAL:
		return
	_position_sync_accum = 0.0
	var local_hero_ref: Node2D = local_hero()
	if local_hero_ref == null or not is_instance_valid(local_hero_ref):
		return
	var pos: Vector2 = local_hero_ref.position
	var facing: Vector2 = local_hero_ref.facing
	if MpIo.is_host():
		# Host pushes its own position to clients directly.
		rpc("_rpc_hero_position", MpIo.local_peer_id, pos, facing)
		# Also broadcast every cached client position so peers see each
		# other (host is the relay).
		for pid in _pending_positions.keys():
			var entry: Dictionary = _pending_positions[pid]
			rpc("_rpc_hero_position", int(pid), Vector2(entry.pos), Vector2(entry.facing))
		_pending_positions.clear()
	else:
		# Client → host. Host rebroadcasts on its next tick.
		rpc_id(1, "_rpc_hero_intent_move", pos, facing)
	# Host also broadcasts enemy position snapshot so remote clients can
	# render moving enemies. Cheap loop; ~30 enemies max in any wave.
	if MpIo.is_host():
		var snapshot: Dictionary = {}
		for nid_v in enemies_by_id.keys():
			var e: Node2D = enemies_by_id[nid_v]
			if e != null and is_instance_valid(e):
				snapshot[int(nid_v)] = e.position
		if not snapshot.is_empty():
			rpc("_rpc_enemy_positions", snapshot)

# ── Damage routing ──────────────────────────────────────────────────────

func client_request_swing(weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int, attack_speed_mult: float = 1.0) -> void:
	# Local hero swung. In solo, the local main.gd already resolved the
	# swing — this helper is only meaningful in multiplayer client mode.
	#
	# attack_speed_mult is the client's local effective_stats.attack_speed
	# at the moment of the swing. Without it the host's per-peer cooldown
	# gate would use the base 1.0 modifier and reject legitimate swings
	# from a client with attack-speed upgrades (PR #43 review). Trust is
	# bounded — main.host_resolve_remote_swing caps the value before
	# applying it.
	if not MpIo.is_multiplayer() or MpIo.is_host():
		return
	rpc_id(1, "_rpc_request_swing", weapon_id, origin, facing, ammo_count, attack_speed_mult)

func host_apply_enemy_damage(enemy_node: Node, amount: float) -> void:
	# Host-only entry. Applies damage locally and broadcasts to clients.
	if not is_instance_valid(enemy_node):
		return
	var nid: int = int(enemy_node.get_meta("network_id", 0))
	if MpIo.is_multiplayer():
		rpc("_rpc_enemy_damaged", nid, amount)
	if enemy_node.has_method("damage"):
		enemy_node.damage(amount)

func host_apply_hero_damage(peer_id: int, amount: float) -> void:
	# Host-arbitrated hero damage. Broadcasts so every peer's HUD updates.
	var hero_ref: Node2D = hero_for_peer(peer_id)
	if hero_ref == null or not is_instance_valid(hero_ref):
		return
	if MpIo.is_multiplayer():
		rpc("_rpc_hero_damaged", peer_id, amount)
	if hero_ref.has_method("damage"):
		hero_ref.damage(amount)

func host_mark_hero_revived(peer_id: int, hp_ratio: float) -> void:
	if MpIo.is_multiplayer():
		rpc("_rpc_hero_revived", peer_id, hp_ratio)
	_apply_hero_revived(peer_id, hp_ratio)

func host_mark_hero_fallen(peer_id: int) -> void:
	if MpIo.is_multiplayer():
		rpc("_rpc_hero_fallen", peer_id)
	_apply_hero_fallen(peer_id)

func client_request_revive(target_peer: int) -> void:
	if not MpIo.is_multiplayer():
		return
	if MpIo.is_host():
		main_node.host_resolve_revive(MpIo.local_peer_id, target_peer)
	else:
		rpc_id(1, "_rpc_request_revive", target_peer)

func client_request_help_ability(target_peer: int) -> void:
	if not MpIo.is_multiplayer():
		return
	if MpIo.is_host():
		main_node.host_resolve_help_ability(MpIo.local_peer_id, target_peer)
	else:
		rpc_id(1, "_rpc_request_help_ability", target_peer)

# ── RPC surface ────────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_enemy(nid: int, enemy_type: String, tile: Vector2i, stat_scale: Dictionary) -> void:
	if MpIo.is_host():
		return
	if enemies_by_id.has(nid):
		return
	_spawn_enemy_local(nid, enemy_type, tile, stat_scale)

@rpc("authority", "unreliable", "call_remote")
func _rpc_hero_position(peer_id: int, pos: Vector2, facing: Vector2) -> void:
	if peer_id == MpIo.local_peer_id:
		return
	var hero_ref: Node2D = hero_for_peer(peer_id)
	if hero_ref == null or not is_instance_valid(hero_ref):
		return
	if hero_ref.has_method("apply_remote_pose"):
		hero_ref.apply_remote_pose(pos, facing)
	else:
		hero_ref.position = pos

@rpc("any_peer", "unreliable", "call_remote")
func _rpc_hero_intent_move(pos: Vector2, facing: Vector2) -> void:
	if not MpIo.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# Cache for next sync tick rather than echoing each move immediately;
	# keeps the rebroadcast at the configured 10Hz cadence.
	_pending_positions[sender] = {"pos": pos, "facing": facing}
	# Apply to the host's local puppet too so the host sees the client move.
	var hero_ref: Node2D = hero_for_peer(sender)
	if hero_ref != null and is_instance_valid(hero_ref) and hero_ref.has_method("apply_remote_pose"):
		hero_ref.apply_remote_pose(pos, facing)

@rpc("authority", "unreliable", "call_remote")
func _rpc_enemy_positions(positions_by_id: Dictionary) -> void:
	for nid_v in positions_by_id.keys():
		var nid: int = int(nid_v)
		if not enemies_by_id.has(nid):
			continue
		var e: Node2D = enemies_by_id[nid]
		if e != null and is_instance_valid(e):
			# Direct write — clients are puppets, no interpolation budget for v1.
			e.position = positions_by_id[nid_v]

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_swing(weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int, attack_speed_mult: float = 1.0) -> void:
	if not MpIo.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if main_node != null and main_node.has_method("host_resolve_remote_swing"):
		main_node.host_resolve_remote_swing(sender, weapon_id, origin, facing, ammo_count, attack_speed_mult)

@rpc("authority", "reliable", "call_remote")
func _rpc_enemy_damaged(nid: int, amount: float) -> void:
	if MpIo.is_host():
		return
	if not enemies_by_id.has(nid):
		return
	var e: Node2D = enemies_by_id[nid]
	if e == null or not is_instance_valid(e):
		return
	if e.has_method("damage"):
		e.damage(amount)
	damage_to_enemy.emit(nid, amount)

@rpc("authority", "reliable", "call_remote")
func _rpc_hero_damaged(peer_id: int, amount: float) -> void:
	if MpIo.is_host():
		return
	var hero_ref: Node2D = hero_for_peer(peer_id)
	if hero_ref == null or not is_instance_valid(hero_ref):
		return
	if hero_ref.has_method("damage"):
		hero_ref.damage(amount)
	damage_to_hero.emit(peer_id, amount)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_revive(target_peer: int) -> void:
	if not MpIo.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if main_node != null and main_node.has_method("host_resolve_revive"):
		main_node.host_resolve_revive(sender, target_peer)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_help_ability(target_peer: int) -> void:
	if not MpIo.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if main_node != null and main_node.has_method("host_resolve_help_ability"):
		main_node.host_resolve_help_ability(sender, target_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_hero_revived(peer_id: int, hp_ratio: float) -> void:
	_apply_hero_revived(peer_id, hp_ratio)

@rpc("authority", "reliable", "call_local")
func _rpc_hero_fallen(peer_id: int) -> void:
	_apply_hero_fallen(peer_id)

@rpc("authority", "reliable", "call_local")
func _rpc_help_ability(caster_peer: int, target_peer: int, ability_id: String) -> void:
	help_ability_cast.emit(caster_peer, target_peer, ability_id)

@rpc("authority", "reliable", "call_local")
func _rpc_wave_state(first_hit_peer: int, composition: Dictionary) -> void:
	# Host-authoritative pick of first-hit hero (BUF-153). Clients
	# adopt this and re-evaluate their HUD veil. Host receives it via
	# call_local so the same code path runs on every peer.
	if main_node != null and main_node.has_method("apply_wave_state"):
		main_node.apply_wave_state(first_hit_peer, composition)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_signature(ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	if not MpIo.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if main_node != null and main_node.has_method("host_resolve_signature"):
		main_node.host_resolve_signature(sender, ability_id, caster_pos, target_pos)

@rpc("authority", "reliable", "call_remote")
func _rpc_signature_visual(_caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	# Visual flash only — actual damage is applied on the host and
	# broadcast via _rpc_enemy_damaged. Re-resolve on the client to get
	# the same swing arc / dash path the resolver produced for the host.
	# Damage application is gated to the host inside main._apply_signature_effect.
	if main_node != null and main_node.has_method("_apply_signature_effects"):
		# v1: just play the host's broadcast effect locally — clients see
		# damage via the separate _rpc_enemy_damaged path. Skipping this
		# replay for now; the swing visual is implicit in the dash / hit
		# flash. M5 wires a dedicated cast-flash visual.
		pass
	# Suppress lint about unused params — they are part of the interface
	# we'll fill in M5 with a cast-flash polish pass.
	var _silence_caster := caster_pos
	var _silence_target := target_pos
	var _silence_ability := ability_id

func _apply_hero_revived(peer_id: int, hp_ratio: float) -> void:
	var hero_ref: Node2D = hero_for_peer(peer_id)
	if hero_ref == null or not is_instance_valid(hero_ref):
		return
	if hero_ref.has_method("apply_revive"):
		hero_ref.apply_revive(hp_ratio)
	hero_revived.emit(peer_id)

func _apply_hero_fallen(peer_id: int) -> void:
	var hero_ref: Node2D = hero_for_peer(peer_id)
	if hero_ref == null or not is_instance_valid(hero_ref):
		return
	if hero_ref.has_method("apply_fallen"):
		hero_ref.apply_fallen()
	hero_fallen.emit(peer_id)

# ── Cleanup ────────────────────────────────────────────────────────────

func clear_enemies() -> void:
	for nid_v in enemies_by_id.keys():
		var e: Node2D = enemies_by_id[nid_v]
		if e != null and is_instance_valid(e):
			e.queue_free()
	enemies_by_id.clear()
	_next_enemy_id = 1

func clear_heroes() -> void:
	for h in heroes_by_peer.values():
		if h != null and is_instance_valid(h):
			h.queue_free()
	heroes_by_peer.clear()
