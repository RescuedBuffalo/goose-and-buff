extends Node
##
## MultiplayerIO — adapter that owns the MultiplayerAPI lifecycle for the
## M4 multiplayer foundation. Registered as an autoload (`MpIo`) so any
## scene can ask "are we hosting?", "what's my hero id?", "who else is
## here?", and so the lobby + main scenes share the same peer + lobby
## state across scene transitions.
##
## All ENet / MultiplayerPeer calls live here. Pure logic for the lobby
## state lives in scripts/logic/lobby_state.gd; this script applies the
## host-authoritative actions to that state and broadcasts snapshots to
## clients via RPCs.
##
## Single-player parity: by default no peer is bound and is_multiplayer()
## returns false. Solo flow (run-start "Stand the watch alone") never
## touches this script — main.gd checks `MpIo.is_multiplayer()` and
## degrades to local-only behavior when false.

const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const LobbyStateClass := preload("res://scripts/logic/lobby_state.gd")

signal hosted(host_code: String)
signal joined(peer_id: int)
signal join_failed(reason: String)
signal left()
signal lobby_updated()
signal peer_state_changed(peer_id: int, state_id: String, hero_id: String)
signal run_started(run_seed: int, hero_assignments: Dictionary)

enum Mode { OFFLINE, HOST, CLIENT }

var mode: int = Mode.OFFLINE
var lobby = null  # LobbyState (RefCounted)
var local_peer_id: int = 0
var local_hero_id: String = ""
# When the host starts the run, this dict is broadcast so every client
# can build the same hero list. peer_id (int) → hero_id (String).
var hero_assignments: Dictionary = {}
# Set at run-start so adapters can deterministically derive the peer
# order without polling. peer_id (int) → slot_index (int 0..2).
var slot_assignments: Dictionary = {}
# Per-peer connection-state cache for HUD copy. peer_id (int) → state_id.
var peer_states: Dictionary = {}
# Cached connection-state copy banner. The HUD reads `last_connection_event`
# directly so a recently-fired transition is visible without subscribing.
var last_connection_event: Dictionary = {}

const _HOST_PEER_ID := 1

func _ready() -> void:
	lobby = LobbyStateClass.new()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ── Public API ────────────────────────────────────────────────────────

func is_multiplayer() -> bool:
	return mode != Mode.OFFLINE

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func host(name_for_self: String = "Host") -> bool:
	# Boot an ENet server on the default port. Returns true on success.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(MultiplayerDataClass.DEFAULT_PORT, MultiplayerDataClass.SLOT_COUNT - 1)
	if err != OK:
		push_warning("MpIo.host: create_server failed (err %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	local_peer_id = _HOST_PEER_ID
	# Generate a fresh host code. RandomNumberGenerator with randomize()
	# so the same dev session can re-host without reusing yesterday's code.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code: String = LobbyStateClass.generate_host_code(rng)
	lobby.set_host_code(code)
	lobby.claim_slot(_HOST_PEER_ID, name_for_self)
	_set_peer_state(_HOST_PEER_ID, MultiplayerDataClass.STATE_CONNECTED, "")
	hosted.emit(code)
	lobby_updated.emit()
	return true

func join(host_address: String, _host_code: String, name_for_self: String = "Joiner") -> bool:
	# Connect to a host on the default port. Host code is currently a
	# voice-only field — ENet has no concept of pairing codes; the host
	# code is for humans to share over Discord and is validated only in
	# that the joiner has to type the right address. M5 can wire a
	# rendezvous server if home-router NAT punching gives trouble.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_address, MultiplayerDataClass.DEFAULT_PORT)
	if err != OK:
		push_warning("MpIo.join: create_client failed (err %d)" % err)
		join_failed.emit("could_not_open_socket")
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	# Stash our display name so the host can adopt it the moment the
	# connection lands. local_peer_id is filled in connected_to_server.
	local_hero_id = ""
	_pending_join_name = name_for_self
	return true

func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	local_peer_id = 0
	local_hero_id = ""
	hero_assignments = {}
	slot_assignments = {}
	peer_states = {}
	if lobby != null:
		lobby.reset()
	left.emit()

func pick_hero(hero_id: String) -> void:
	# Local-side: send a "I want this hero" intent. On the host, applied
	# directly. On a client, RPCed to the host who validates and broadcasts.
	if mode == Mode.OFFLINE:
		return
	if is_host():
		_apply_hero_pick(_HOST_PEER_ID, hero_id)
	else:
		rpc_id(_HOST_PEER_ID, "_rpc_request_hero_pick", hero_id)

func set_ready(is_ready: bool) -> void:
	if mode == Mode.OFFLINE:
		return
	if is_host():
		_apply_ready(_HOST_PEER_ID, is_ready)
	else:
		rpc_id(_HOST_PEER_ID, "_rpc_request_ready", is_ready)

func light_the_lantern(run_seed: int) -> void:
	# Host-only: lock in the lobby and broadcast run-start. Each peer
	# transitions to main.tscn off the same broadcast so nobody gets there
	# early.
	if not is_host():
		return
	if not lobby.is_ready_to_start():
		return
	hero_assignments = {}
	slot_assignments = {}
	for slot in lobby.snapshot():
		var pid: int = int(slot.peer_id)
		if pid == 0:
			continue
		hero_assignments[pid] = String(slot.hero_id)
		slot_assignments[pid] = int(slot.slot_index)
	rpc("_rpc_run_started", run_seed, hero_assignments, slot_assignments)
	# Local-side mirror: the @rpc has call_local on it, but call out to
	# the same handler explicitly so the host sees its own transition
	# even if call_local timing changes.
	# (The local ack is delivered by the rpc call_local annotation below.)

# ── RPC surface ───────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_request_hero_pick(hero_id: String) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_hero_pick(sender, hero_id)

@rpc("any_peer", "reliable")
func _rpc_request_ready(is_ready: bool) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_ready(sender, is_ready)

@rpc("any_peer", "reliable")
func _rpc_introduce(name_for_self: String) -> void:
	# Sent by clients on connected_to_server. The host claims a slot for
	# them and broadcasts the new lobby state.
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if lobby.claim_slot(sender, name_for_self) >= 0:
		_set_peer_state(sender, MultiplayerDataClass.STATE_CONNECTED, "")
		_broadcast_lobby_snapshot()

@rpc("authority", "reliable")
func _rpc_lobby_snapshot(snap: Array, code: String) -> void:
	if lobby == null:
		return
	lobby.adopt_snapshot(snap)
	lobby.set_host_code(code)
	lobby_updated.emit()

@rpc("authority", "reliable", "call_local")
func _rpc_run_started(run_seed: int, assignments: Dictionary, slots: Dictionary) -> void:
	hero_assignments = assignments.duplicate(true)
	slot_assignments = slots.duplicate(true)
	if hero_assignments.has(local_peer_id):
		local_hero_id = String(hero_assignments[local_peer_id])
	GameState.set_run_config(run_seed, local_hero_id)
	run_started.emit(run_seed, hero_assignments)

@rpc("authority", "reliable", "call_local")
func _rpc_peer_state(peer_id: int, state_id: String, hero_id: String) -> void:
	peer_states[peer_id] = state_id
	last_connection_event = {
		"peer_id": peer_id,
		"state_id": state_id,
		"hero_id": hero_id,
	}
	peer_state_changed.emit(peer_id, state_id, hero_id)

# ── Internals ─────────────────────────────────────────────────────────

var _pending_join_name: String = "Joiner"

func _apply_hero_pick(peer_id: int, hero_id: String) -> void:
	if lobby.pick_hero(peer_id, hero_id):
		_broadcast_lobby_snapshot()

func _apply_ready(peer_id: int, is_ready: bool) -> void:
	if lobby.set_ready(peer_id, is_ready):
		_broadcast_lobby_snapshot()

func _broadcast_lobby_snapshot() -> void:
	if not is_host():
		return
	var snap: Array = lobby.snapshot()
	var code: String = lobby.host_code
	# Local listeners (the host's own lobby UI) react to this signal too;
	# the RPC is fired call_local so all peers, including the host, run
	# the same adopt_snapshot path.
	rpc("_rpc_lobby_snapshot", snap, code)
	# Host adopts its own snapshot directly so the local lobby UI updates
	# even though "authority" RPCs don't loop back without call_local.
	lobby.adopt_snapshot(snap)
	lobby.set_host_code(code)
	lobby_updated.emit()

func _set_peer_state(peer_id: int, state_id: String, hero_id: String) -> void:
	peer_states[peer_id] = state_id
	last_connection_event = {
		"peer_id": peer_id,
		"state_id": state_id,
		"hero_id": hero_id,
	}
	peer_state_changed.emit(peer_id, state_id, hero_id)
	if is_host():
		# Mirror to clients so their HUDs render the same banner.
		rpc("_rpc_peer_state", peer_id, state_id, hero_id)

func resolve_hero_for_peer(peer_id: int) -> String:
	if hero_assignments.has(peer_id):
		return String(hero_assignments[peer_id])
	# Fallback to lobby state — covers the lobby scene before run-start.
	if lobby != null:
		return lobby.hero_for_peer(peer_id)
	return ""

func slot_for_peer(peer_id: int) -> int:
	if slot_assignments.has(peer_id):
		return int(slot_assignments[peer_id])
	if lobby != null:
		var s: Dictionary = lobby.slot_for_peer(peer_id)
		return int(s.get("slot_index", -1))
	return -1

# ── Multiplayer signal handlers ───────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# Client side: the host connected to us (peer_id == 1). Wait for the
	# server to push the lobby snapshot. Host side: a joiner appeared —
	# wait for their _rpc_introduce, which assigns their slot.
	if not is_host():
		return
	# Defensive: a previous run's peer reconnecting after a drop within
	# the run's lifetime might re-fire connected. Treat as fresh.
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host():
		var hero_id: String = resolve_hero_for_peer(peer_id)
		# In-lobby disconnects free the slot; in-run disconnects flip the
		# peer to "dropped" (the gameplay scene listens and hands the
		# hero to the AI placeholder until reconnect).
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path.find("lobby.tscn") != -1:
			lobby.release_slot(peer_id)
			_set_peer_state(peer_id, MultiplayerDataClass.STATE_DROPPED, hero_id)
			_broadcast_lobby_snapshot()
		else:
			_set_peer_state(peer_id, MultiplayerDataClass.STATE_DROPPED, hero_id)

func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	joined.emit(local_peer_id)
	# Introduce ourselves so the host can give us a slot.
	rpc_id(_HOST_PEER_ID, "_rpc_introduce", _pending_join_name)

func _on_connection_failed() -> void:
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = null
	join_failed.emit("connection_failed")

func _on_server_disconnected() -> void:
	# Host went away. Surface the host-dropped banner; the gameplay scene
	# (or the lobby scene) reads this and routes everyone back to lobby.
	_set_peer_state(_HOST_PEER_ID, MultiplayerDataClass.STATE_HOST_DROPPED, "")
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = null
	left.emit()
