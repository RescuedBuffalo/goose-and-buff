extends Node
##
## Combat plumbing router (BUF-164). Bridges CombatSystem signals into
## scene-tree mutation, owns enemy lifecycle wiring, and routes hero
## damage through replication so client-owned heroes see hits.
##
## Public surface used by main.gd:
##   attach(combat, inventory, replication, sector, telemetry)
##   on_enemy_due(enemy_type, slot_index)        — wired to wave_director
##   on_wave_ended(round_index)                  — wired to wave_director
##   host_resolve_remote_swing(peer, weapon_id, origin, facing, ammo) — public,
##                                                  forwarded by main for replication.gd
##
## Signals:
##   enemy_killed(enemy_type)   — main listens to bump _enemies_felled counter
##
## Combat damage dealt by the local hero flows through CombatSystem's
## damage_dealt signal which we re-emit (after MP routing) so the visual
## layer + counters fire identically across host and clients.

const Waves := preload("res://data/waves.gd")
const ProjectileScene := preload("res://scenes/projectile.tscn")

signal enemy_killed(enemy_type: String)

var combat: CombatSystem = null
var inventory: InventorySystem = null
var replication: Node = null
var sector: Node = null
var telemetry: Telemetry = null
var wave_director: WaveDirector = null

func attach(
	combat_system: CombatSystem,
	inventory_system: InventorySystem,
	replication_node: Node,
	sector_node: Node,
	telemetry_node: Telemetry,
	wave_director_ref: WaveDirector,
) -> void:
	combat = combat_system
	inventory = inventory_system
	replication = replication_node
	sector = sector_node
	telemetry = telemetry_node
	wave_director = wave_director_ref
	combat.damage_dealt.connect(_on_combat_damage)
	combat.projectile_requested.connect(_on_projectile_requested)
	combat.ammo_consumed.connect(_on_ammo_consumed)

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
	# Parent under the scene root so ysorting + scene cleanup work.
	get_tree().current_scene.add_child(arrow)
	arrow.position = origin
	arrow.configure(direction, range_px, damage, speed_px)
	arrow.hit_target.connect(_on_projectile_hit)

func _on_projectile_hit(target_ref, amount: float) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	# Route through combat.damage_dealt so the same listeners that handle
	# melee hits (damage application + floating-number visuals) fire for
	# ranged hits too. Without this, bow hits applied damage but never
	# showed the floating number, since combat_visuals only listens to
	# combat.damage_dealt.
	combat.damage_dealt.emit(target_ref, amount)

func _on_ammo_consumed(item_id: String, count: int) -> void:
	if item_id.is_empty() or count <= 0:
		return
	if inventory != null:
		inventory.remove_item(item_id, count)

# ── Wave plumbing ────────────────────────────────────────────────────

func on_enemy_due(enemy_type: String, slot_index: int) -> void:
	# Multiplayer: only the host's WaveDirector should fire enemy_due
	# transitions. Clients run wave_director locally for HUD timing but
	# they ignore enemy_due so they don't double-spawn — replication
	# RPCs handle visible enemy node creation on clients.
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

func _on_enemy_died(_enemy: Node, enemy_type: String) -> void:
	wave_director.note_enemy_killed()
	enemy_killed.emit(enemy_type)
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

func on_wave_ended(round_index: int) -> void:
	# Free any enemies that didn't reach the core in time. Clients run
	# their own wave_director.tick so they reach this branch too — the
	# host's broadcast-driven cleanup of remote enemies is separate.
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	if telemetry != null:
		telemetry.log("wave_end", {
			"round_index": round_index,
		})

# ── Multiplayer client-swing resolution ──────────────────────────────

func host_resolve_remote_swing(peer_id: int, weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int) -> void:
	# Run the swing on the host using the requesting peer's facing /
	# weapon. Note: the host's own combat.tick handles cooldown for the
	# host's local hero — for remote peers we don't track per-peer
	# cooldown (clients gate themselves with their local CombatSystem).
	#
	# NOTE: stat modifiers default to 1.0 — per-peer modifier propagation
	# is tracked in BUF-169.
	if not MpIo.is_host():
		return
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	var caster_hero: Node2D = replication.hero_for_peer(peer_id)
	if caster_hero == null or not is_instance_valid(caster_hero):
		return
	# Use a fresh CombatSystem for client swings so the host's combat
	# cooldown isn't blocked by a remote peer's swing.
	var temp_combat := CombatSystem.new()
	# Connect damage_dealt + projectile_requested to the same handlers
	# that the host's main.gd uses, so the host applies damage and
	# broadcasts via replication.
	#
	# Ammo: deliberately NOT connected. The remote peer owns its own
	# inventory; charging a remote bow shot to the host's inventory
	# would drain the host's arrows whenever a client fires (and the
	# client would never see its own count drop, since the swing intent
	# never touches local inventory either). Clients deduct ammo
	# locally before sending the intent.
	temp_combat.damage_dealt.connect(_on_combat_damage)
	temp_combat.projectile_requested.connect(_on_projectile_requested)
	# Mirror swing_started to the visual layer so the host sees the
	# remote peer's swing arc (and so do the other clients via the
	# replication broadcast, since combat_visuals listens locally).
	temp_combat.swing_started.connect(combat.swing_started.emit)
	temp_combat.resolve_swing(origin, facing, weapon_id, enemies, ammo_count)
