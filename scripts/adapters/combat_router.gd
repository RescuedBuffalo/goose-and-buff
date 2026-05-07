extends Node
##
## Combat plumbing router (BUF-164). Bridges CombatSystem signals into
## scene-tree mutation, owns enemy lifecycle wiring, and routes hero
## damage through replication so client-owned heroes see hits.
##
## Public surface used by main.gd:
##   attach(combat, inventory, replication, sector, telemetry, wave_director)
##   on_enemy_due(enemy_type, slot_index)        — wired to wave_director
##   on_wave_ended(round_index)                  — wired to wave_director
##   tick_remote_combats(delta)                  — host-only cooldown ticks
##   clear_remote_combats()                      — called from run_lifecycle.start_run
##   host_resolve_remote_swing(peer, weapon_id, origin, facing, ammo, attack_speed_mult)
##                                                  forwarded by main for replication.gd
##
## Signals:
##   enemy_killed(enemy_type)   — main listens to bump enemies_felled counter
##
## Combat damage dealt by the local hero flows through CombatSystem's
## damage_dealt signal which we re-emit (after MP routing) so the visual
## layer + counters fire identically across host and clients.

const Waves := preload("res://data/waves.gd")
const ProjectileScene := preload("res://scenes/projectile.tscn")

# Upper bound the host applies to a client's claimed attack_speed_mult.
# The maximum legitimate stack of attack-speed upgrades in M2 is well
# under 2x (Goose open_throat 0.15 + Buffalo braced_shoulders 0.10 +
# shared_oilskin_grip 0.12 + similar = ~0.4 → 1.4x), so 2.5x leaves
# headroom for future upgrades while still rejecting anyone trying to
# pass a 100x-speed claim. Per-peer effective_stats replication ships
# in M5; until then this cap is the right trade-off (PR #43 review).
const MAX_REMOTE_ATTACK_SPEED_MULT := 2.5

signal enemy_killed(enemy_type: String)

var combat: CombatSystem = null
var inventory: InventorySystem = null
var replication: Node = null
var sector: Node = null
var telemetry: Telemetry = null
var wave_director: WaveDirector = null
# Per-peer cached CombatSystem instances used by host_resolve_remote_swing
# so the host can reject swing intents that arrive faster than the
# weapon cooldown allows. The previous implementation built a fresh
# CombatSystem per RPC, which had no memory of the prior swing — a
# non-host peer that bypassed the client UI could fire RPCs at any rate
# and the host would apply damage every time. Each entry here lives for
# the run; cleared via clear_remote_combats() on run-start (PR #43 review).
var _remote_combat_by_peer: Dictionary = {}  # peer_id (int) → CombatSystem

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

func on_wave_ended(_round_index: int) -> void:
	# Free any enemies that didn't reach the core in time. Clients run
	# their own wave_director.tick so they reach this branch too — the
	# host's broadcast-driven cleanup of remote enemies is separate.
	# Telemetry for the `wave_end` event is emitted by run_lifecycle
	# (it owns the nights_survived counter the schema requires).
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()

# ── Multiplayer client-swing resolution ──────────────────────────────

func host_resolve_remote_swing(peer_id: int, weapon_id: String, origin: Vector2, facing: Vector2, ammo_count: int, attack_speed_mult: float = 1.0) -> void:
	# Authoritative remote-swing resolver. PR #43 review:
	# - The previous implementation built a fresh CombatSystem per RPC,
	#   which made the can_swing() check vacuous; replaced with a
	#   per-peer cached CombatSystem that ticks alongside the host's own
	#   combat (see _get_or_create_remote_combat).
	# - The host originally used a 1.0 attack_speed modifier on the
	#   per-peer combat, which silently rejected legitimate swings from
	#   a client with attack-speed upgrades (the client's note_swing_cooldown
	#   used the upgraded mult, so they sent the next intent before the
	#   host's slower cooldown elapsed). Now the client passes its local
	#   effective attack_speed in the swing intent and the host applies
	#   it (capped to MAX_REMOTE_ATTACK_SPEED_MULT) before the can_swing
	#   gate. Per-peer effective_stats replication is still M5 work —
	#   this is the smallest fix that lets upgraded clients play correctly
	#   without trusting an unbounded multiplier.
	#
	# Ammo: deliberately NOT connected on the per-peer combat. The remote
	# peer owns its own inventory; charging a remote bow shot to the
	# host's inventory would drain the host's arrows whenever a client
	# fires. Clients deduct ammo locally before sending the intent.
	if not MpIo.is_host():
		return
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	var caster_hero: Node2D = replication.hero_for_peer(peer_id)
	if caster_hero == null or not is_instance_valid(caster_hero):
		return
	var per_peer_combat: CombatSystem = _get_or_create_remote_combat(peer_id)
	# Apply the client's claimed attack_speed mult, capped. damage_mult
	# stays 1.0 (per-peer damage replication is M5); attack_range_bonus
	# is irrelevant here because the host re-derives range from weapon +
	# the bonus on its own combat. Setting modifiers before can_swing()
	# means a client whose attack-speed upgrade was just purchased gets
	# the new cooldown applied to the *current* swing's gate, not just
	# the next one.
	var capped_speed: float = clamp(attack_speed_mult, 0.1, MAX_REMOTE_ATTACK_SPEED_MULT)
	per_peer_combat.set_stat_modifiers(1.0, capped_speed, 0.0)
	if not per_peer_combat.can_swing():
		# Reject early — drop the intent silently. The client already
		# played its prediction-arc; if a malicious client sent the RPC
		# without a local swing, dropping the damage application is the
		# whole point.
		return
	per_peer_combat.resolve_swing(origin, facing, weapon_id, enemies, ammo_count)

func _get_or_create_remote_combat(peer_id: int) -> CombatSystem:
	# Lazily build a CombatSystem per remote peer the first time the host
	# resolves a swing for them. Wires the same damage / projectile /
	# swing-visual signals the host's local combat uses so applied damage
	# routes through replication and the swing arc renders on every peer.
	if _remote_combat_by_peer.has(peer_id):
		return _remote_combat_by_peer[peer_id]
	var c := CombatSystem.new()
	c.damage_dealt.connect(_on_combat_damage)
	c.projectile_requested.connect(_on_projectile_requested)
	# Mirror swing_started to the host's combat signal so combat_visuals
	# (which listens to the host's combat) draws the remote arc, and the
	# replication broadcast carries it to other clients.
	c.swing_started.connect(combat.swing_started.emit)
	_remote_combat_by_peer[peer_id] = c
	return c

func tick_remote_combats(delta: float) -> void:
	# Drain all per-peer cooldowns alongside the host's local one.
	for c in _remote_combat_by_peer.values():
		c.tick(delta)

func clear_remote_combats() -> void:
	# Reset between runs and on full teardown so a stale cooldown can't
	# survive into the next run.
	_remote_combat_by_peer.clear()
