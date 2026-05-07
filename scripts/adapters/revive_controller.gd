extends Node
##
## Revive + downed timer + help-ability cooldown coordinator (BUF-152
## / BUF-154). Split out of main.gd in BUF-164.
##
## Owns:
##   _help_ability_cooldowns   — per-peer cooldown ticks for the local HUD
##   _revive_hold_target       — peer_id of teammate the local hero is
##                                holding R on
##   _revive_hold_seconds      — accumulated hold time
##
## Public surface used by main.gd:
##   attach(local_hero_provider, sector, replication, telemetry)
##   tick(delta)                 — drives cooldown decay + downed timers
##                                  + revive-input accumulation
##   tick_revive_input(delta)    — explicit if main wants finer control
##   request_help_ability(target_peer)
##   help_ability_cooldown_for(peer_id) -> float
##   help_target_peer_at(world_pos, wave_first_hit_peer) -> int
##   host_resolve_revive(caster_peer, target_peer) — replication entry
##
## The router holds *no* hero reference directly — it queries the local
## hero through a Callable provider so it remains valid across hero
## respawns / multiplayer puppet rebinds.

const MultiplayerDataClass := preload("res://data/multiplayer.gd")

# peer_id → seconds remaining
var _help_ability_cooldowns: Dictionary = {}
var _revive_hold_target: int = 0  # peer_id of revive target the local hero is currently reviving
var _revive_hold_seconds: float = 0.0

var sector: Node = null
var replication: Node = null
var telemetry: Telemetry = null
# Callable returning the local hero Node2D, or null. Used so the router
# doesn't pin a stale ref across respawns.
var _local_hero_provider: Callable = Callable()

func attach(local_hero_provider: Callable, sector_node: Node, replication_node: Node, telemetry_node: Telemetry) -> void:
	_local_hero_provider = local_hero_provider
	sector = sector_node
	replication = replication_node
	telemetry = telemetry_node

func reset() -> void:
	_help_ability_cooldowns.clear()
	_revive_hold_target = 0
	_revive_hold_seconds = 0.0

func tick(delta: float) -> void:
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
	tick_revive_input(delta)

func help_ability_cooldown_for(peer_id: int) -> float:
	return float(_help_ability_cooldowns.get(peer_id, 0.0))

func request_help_ability(target_peer: int) -> void:
	# Local-side gate: cooldown check, valid target, alive caster. Stamps
	# the local cooldown for HUD feedback; host validates again.
	var hero: Node2D = _resolve_local_hero()
	if hero == null or bool(hero.get("is_downed")):
		return
	var local_pid: int = MpIo.local_peer_id if MpIo.is_multiplayer() else 1
	var cd: float = float(_help_ability_cooldowns.get(local_pid, 0.0))
	if cd > 0.0:
		return
	if target_peer == local_pid or target_peer == 0:
		return
	_help_ability_cooldowns[local_pid] = MultiplayerDataClass.HELP_ABILITY_COOLDOWN
	if MpIo.is_multiplayer():
		replication.client_request_help_ability(target_peer)
	# Solo path is a no-op — there are no teammates — but keeping the
	# call path defined makes testing easier.

func help_target_peer_at(world_pos: Vector2, wave_first_hit_peer: int) -> int:
	# Returns the peer_id of a teammate near the click, or 0 if none.
	# Used for the "click on the friend" alternate to portrait-click
	# targeting. HUD calls request_help_ability_at_peer directly for
	# portrait clicks.
	var hero: Node2D = _resolve_local_hero()
	if hero == null:
		return 0
	for h in replication.all_heroes():
		if h == hero:
			continue
		if not is_instance_valid(h):
			continue
		if (h.position - world_pos).length() < 32.0:
			return int(h.get_meta("peer_id", 0))
	# Quick-target: double-tap E (just-pressed this frame) picks the
	# most-in-combat teammate. Held-only acts as targeting cursor.
	if Input.is_action_just_pressed("help_ability"):
		# Picks the peer marked first-hit-hero this wave (the spine
		# mechanic's "most in combat") if any; else 0.
		if wave_first_hit_peer != 0:
			return wave_first_hit_peer
		return 0
	return 0

func tick_revive_input(delta: float) -> void:
	# Local hero holding R near a downed teammate accumulates progress.
	# Once the hold reaches REVIVE_HOLD_SECONDS, fire revive intent.
	var hero: Node2D = _resolve_local_hero()
	if hero == null or bool(hero.get("is_downed")):
		_revive_hold_target = 0
		_revive_hold_seconds = 0.0
		_clear_visible_revive_progress()
		return
	if not Input.is_action_pressed("revive"):
		_revive_hold_target = 0
		_revive_hold_seconds = 0.0
		_clear_visible_revive_progress()
		return
	var target: Node2D = _nearest_downed_teammate(hero)
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

func host_resolve_revive(caster_peer: int, target_peer: int) -> void:
	# Host-only entry. Validates the caster is in range, then broadcasts
	# the revive via replication so every peer's HUD updates.
	if not (MpIo.is_host() or not MpIo.is_multiplayer()):
		return
	var caster: Node2D = replication.hero_for_peer(caster_peer)
	var target: Node2D = replication.hero_for_peer(target_peer)
	if caster == null or target == null:
		return
	if not bool(target.get("is_downed")) or bool(target.get("is_fallen")):
		return
	if sector.tile_distance(caster.current_tile, target.current_tile) > MultiplayerDataClass.REVIVE_RANGE_TILES:
		return
	replication.host_mark_hero_revived(target_peer, MultiplayerDataClass.FALLEN_RESPAWN_HP_RATIO)
	if telemetry != null:
		telemetry.log("hero_revived", {"caster_peer": caster_peer, "target_peer": target_peer})

# ── internals ─────────────────────────────────────────────────────────

func _resolve_local_hero() -> Node2D:
	if _local_hero_provider.is_null():
		return null
	var ref = _local_hero_provider.call()
	if ref == null or not is_instance_valid(ref):
		return null
	return ref as Node2D

func _tick_downed_timers(_delta: float) -> void:
	# Per-frame check: any host-tracked hero whose downed timer hit zero
	# without revive transitions to fallen via replication broadcast.
	if replication == null:
		return
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

func _nearest_downed_teammate(hero: Node2D) -> Node2D:
	if hero == null or replication == null or sector == null:
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

func _clear_visible_revive_progress() -> void:
	if replication == null:
		return
	for h in replication.all_heroes():
		var rp_val = h.get("revive_progress_seconds") if h != null and is_instance_valid(h) else null
		if rp_val != null and float(rp_val) != 0.0:
			h.revive_progress_seconds = 0.0
			h.queue_redraw()
