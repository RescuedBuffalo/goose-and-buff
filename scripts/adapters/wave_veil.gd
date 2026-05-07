extends Node
##
## Wave veil + first-hit hero coordinator (BUF-153). Owns the host-side
## pick of the first-hit peer when a wave starts, the LOS-based
## visibility lift for non-first-hit teammates, and the seasonal-frame
## banner copy. Split out of main.gd in BUF-164.
##
## Public surface used by main.gd:
##   attach(sector, replication, hud, telemetry)
##   reset()
##   on_wave_started(round_index, composition)   — connected to wave_director.wave_started
##   apply_wave_state(first_hit_peer, composition) — landing point on every peer
##   tick_visibility()                            — host-only LOS recompute
##   wave_first_hit_peer() / wave_first_hit_hero_id() / is_wave_visible_to_local()
##
## Stays in adapter layer because it touches replication RPCs, HUD,
## telemetry, and the MpIo autoload. The actual veil rule (first-hit
## privileges, distance threshold) is documented inline; if it grows
## complex enough to merit a pure-logic counterpart, lift the picker
## into scripts/logic/.

const Sectors := preload("res://data/sectors.gd")
const Waves := preload("res://data/waves.gd")
const MultiplayerDataClass := preload("res://data/multiplayer.gd")

# Distance (in tiles) at which a non-first-hit hero's veil lifts.
# 6 was the original tuning; centralized here so a designer can tune
# it without grepping main.gd.
const LOS_THRESHOLD_TILES := 6

var sector: Node = null
var replication: Node = null
var hud: Node = null
var telemetry: Telemetry = null

# 0 = no wave active / no first-hit chosen yet.
var first_hit_peer: int = 0
# Peer ids that have line-of-sight on the wave.
var visible_to: Array = []
# Last full composition for veil-on-LOS rebroadcast.
var veiled_composition: Dictionary = {}
# Front rotation index — bumped each wave so successive nights pick a
# different anchor edge.
var front_rotation_index: int = 0
# Round index stashed at on_wave_started so apply_wave_state can attach
# it to telemetry without re-deriving from wave_director.
var pending_round_index: int = 0

func attach(sector_node: Node, replication_node: Node, hud_node: Node, telemetry_node: Telemetry) -> void:
	sector = sector_node
	replication = replication_node
	hud = hud_node
	telemetry = telemetry_node

func reset() -> void:
	first_hit_peer = 0
	visible_to = []
	veiled_composition = {}
	front_rotation_index = 0
	pending_round_index = 0

func on_wave_started(round_index: int, composition: Dictionary) -> void:
	# BUF-153 spine. Only the host picks the first-hit hero and broadcasts
	# via _rpc_wave_state. Banner + telemetry are deferred to
	# apply_wave_state so every peer renders off the same authoritative
	# state. Without this discipline, a client's wave_started.emit (from
	# its own deterministic wave_director.tick) ran before the host's
	# RPC arrived, first_hit_peer was 0, and the directional callout
	# leaked to non-first-hit heroes — defeating the info-asymmetric
	# mechanic.
	#
	# In solo, host-or-not-multiplayer collapses to the local pick and
	# call_local fires apply_wave_state synchronously — single peer,
	# single banner, no race.
	pending_round_index = round_index
	if MpIo.is_host() or not MpIo.is_multiplayer():
		var first_hit: int = pick_first_hit_peer()
		if MpIo.is_multiplayer():
			replication.rpc("_rpc_wave_state", first_hit, composition)
		else:
			apply_wave_state(first_hit, composition)
	# Else (client): nothing to render yet. apply_wave_state stamps
	# composition + first_hit_peer when the host's RPC lands.

func apply_wave_state(first_hit_peer_id: int, composition: Dictionary) -> void:
	# Replication.gd routes the host's authoritative wave state here so
	# every peer (including the host, via call_local) lands on the same
	# first_hit_peer + composition.
	first_hit_peer = first_hit_peer_id
	visible_to = [first_hit_peer_id] if first_hit_peer_id != 0 else []
	veiled_composition = composition.duplicate(true)
	_render_wave_banner(pending_round_index, composition)

func is_wave_visible_to_local() -> bool:
	# HUD reads this to decide between "show full composition" and
	# "show only in-combat veil". In solo, always visible.
	if not MpIo.is_multiplayer():
		return true
	if first_hit_peer == 0:
		return true
	return MpIo.local_peer_id in visible_to or MpIo.local_peer_id == first_hit_peer

func wave_first_hit_peer() -> int:
	return first_hit_peer

func wave_first_hit_hero_id() -> String:
	return MpIo.resolve_hero_for_peer(first_hit_peer)

func tick_visibility() -> void:
	# Host-only: figure out which non-first-hit teammates have walked
	# within line-of-sight of the wave (using tile-distance proximity to
	# any spawning enemy). When a peer crosses the threshold, the host
	# broadcasts a "veil-lifted" RPC for that peer.
	if first_hit_peer == 0:
		return
	if replication == null or sector == null:
		return
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	if enemies.is_empty():
		return
	var newly_visible: Array = []
	for h in replication.all_heroes():
		if h == null or not is_instance_valid(h):
			continue
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == first_hit_peer:
			continue
		if pid in visible_to:
			continue
		var hero_tile: Vector2i = h.current_tile
		for e in enemies:
			if not is_instance_valid(e):
				continue
			if sector.tile_distance(hero_tile, e.current_tile) <= LOS_THRESHOLD_TILES:
				newly_visible.append(pid)
				break
	for pid in newly_visible:
		visible_to.append(pid)
		MpIo.rpc("_rpc_peer_state", pid, "veil_lifted", "")

# ── internals ─────────────────────────────────────────────────────────

func _render_wave_banner(round_index: int, composition: Dictionary) -> void:
	# Renders the seasonal-frame call-out + telemetry for the current
	# wave. Voice rule: the directional call-out is privileged info —
	# only the first-hit hero (or the solo player) sees it. Everyone
	# else hears "X is in combat. Listen for the call."
	var shout: String = ""
	var first_hit_hero_id: String = MpIo.resolve_hero_for_peer(first_hit_peer)
	if MpIo.is_multiplayer() and first_hit_peer != MpIo.local_peer_id and first_hit_peer != 0:
		shout = "%s is in combat. Listen for the call." % first_hit_hero_id
	else:
		var direction: String = front_direction_for(front_rotation_index)
		shout = "The cold comes from the %s — %s" % [direction, str(composition.get("banner", "RAID")).to_lower()]
	if hud != null and hud.has_method("show_banner"):
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
			"first_hit_peer": first_hit_peer,
			"first_hit_hero_id": first_hit_hero_id,
		})
		telemetry.log("wave_first_hit_hero", {
			"peer_id": first_hit_peer,
			"hero_id": first_hit_hero_id,
			"round_index": round_index,
		})
	# Rotate the front for the next wave so successive nights fire from
	# different directions across a 3-night run.
	front_rotation_index = (front_rotation_index + 1) % MultiplayerDataClass.FRONT_ROTATION.size()

func pick_first_hit_peer() -> int:
	# Choose the peer whose hero is closest to the rotating front. In
	# solo this collapses to the local hero. The default-front map per
	# hero gives a tie-break: heroes near their associated front are
	# preferred over heroes who happened to wander there — keeps the
	# spine readable across runs.
	var direction: String = MultiplayerDataClass.FRONT_ROTATION[front_rotation_index]
	var heroes: Array = replication.all_heroes() if replication != null else []
	if heroes.is_empty():
		return 0
	if heroes.size() == 1:
		return int(heroes[0].get_meta("peer_id", 0))
	var anchor_tile: Vector2i = front_anchor_tile(direction)
	var best_pid: int = 0
	var best_score: float = INF
	for h in heroes:
		var pid: int = int(h.get_meta("peer_id", 0))
		if pid == 0 or bool(h.get("is_fallen")):
			continue
		var d: float = float(sector.tile_distance(h.current_tile, anchor_tile))
		var hero_id: String = String(h.get_meta("hero_id", ""))
		if MultiplayerDataClass.HERO_FRONT_DEFAULT.get(hero_id, "") == direction:
			d -= 1.5
		if d < best_score:
			best_score = d
			best_pid = pid
	return best_pid

func front_anchor_tile(direction: String) -> Vector2i:
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

func front_direction_for(idx: int) -> String:
	return String(MultiplayerDataClass.FRONT_ROTATION[idx % MultiplayerDataClass.FRONT_ROTATION.size()])
