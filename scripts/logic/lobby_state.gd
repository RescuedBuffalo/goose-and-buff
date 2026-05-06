class_name LobbyState extends RefCounted
##
## Pure lobby state machine. Three slots, each tracking which peer holds
## the slot, which hero they've picked, and whether they've signaled
## ready. The host owns this state; clients receive serialized snapshots
## via RPCs in the multiplayer adapter. No scene-tree references here —
## this file is a state container with operations and validation.
##
## Slot shape:
##   { "slot_index": int, "peer_id": int, "hero_id": String, "ready": bool, "name": String }
##
## peer_id == 0 means an empty slot. hero_id "" means joined but not
## yet picked. ready=true on every slot is the gating condition for
## "Light the lantern".

const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const Heroes := preload("res://data/heroes.gd")

signal slots_changed()
signal host_code_changed(code: String)
signal ready_to_start_changed(ready_to_start: bool)

var slots: Array = []
var host_code: String = ""

func _init() -> void:
	reset()

func reset() -> void:
	slots = []
	for i in MultiplayerDataClass.SLOT_COUNT:
		slots.append({
			"slot_index": i,
			"peer_id": 0,
			"hero_id": "",
			"ready": false,
			"name": "",
		})
	host_code = ""
	slots_changed.emit()
	host_code_changed.emit(host_code)
	ready_to_start_changed.emit(false)

func set_host_code(code: String) -> void:
	if host_code == code:
		return
	host_code = code
	host_code_changed.emit(host_code)

func claim_slot(peer_id: int, name: String = "") -> int:
	# Returns the assigned slot_index, or -1 if the lobby is full or peer
	# is already in. Idempotent: a peer that's already in a slot keeps it.
	for slot in slots:
		if int(slot.peer_id) == peer_id:
			return int(slot.slot_index)
	for slot in slots:
		if int(slot.peer_id) == 0:
			slot.peer_id = peer_id
			slot.name = name
			slot.hero_id = ""
			slot.ready = false
			slots_changed.emit()
			ready_to_start_changed.emit(_is_ready_to_start())
			return int(slot.slot_index)
	return -1

func release_slot(peer_id: int) -> void:
	var dirty := false
	for slot in slots:
		if int(slot.peer_id) == peer_id:
			slot.peer_id = 0
			slot.hero_id = ""
			slot.ready = false
			slot.name = ""
			dirty = true
	if dirty:
		slots_changed.emit()
		ready_to_start_changed.emit(_is_ready_to_start())

func pick_hero(peer_id: int, hero_id: String) -> bool:
	# A peer picks a hero. Rejected if another (occupied) slot already
	# claims that hero — heroes are unique-per-run. Picking the same hero
	# the peer already has is a no-op and returns true.
	if not Heroes.ALL.has(hero_id):
		return false
	for slot in slots:
		if int(slot.peer_id) != 0 and int(slot.peer_id) != peer_id and String(slot.hero_id) == hero_id:
			return false
	for slot in slots:
		if int(slot.peer_id) == peer_id:
			slot.hero_id = hero_id
			# Picking a new hero re-clears ready so the player has to
			# explicitly confirm again. Voice contract: locking in is a
			# decision, not a side effect.
			slot.ready = false
			slots_changed.emit()
			ready_to_start_changed.emit(_is_ready_to_start())
			return true
	return false

func set_ready(peer_id: int, is_ready: bool) -> bool:
	# A peer can only ready up if they've picked a hero.
	for slot in slots:
		if int(slot.peer_id) == peer_id:
			if is_ready and String(slot.hero_id).is_empty():
				return false
			slot.ready = is_ready
			slots_changed.emit()
			ready_to_start_changed.emit(_is_ready_to_start())
			return true
	return false

func is_ready_to_start() -> bool:
	return _is_ready_to_start()

func filled_slot_count() -> int:
	var n := 0
	for slot in slots:
		if int(slot.peer_id) != 0:
			n += 1
	return n

func slot_for_peer(peer_id: int) -> Dictionary:
	for slot in slots:
		if int(slot.peer_id) == peer_id:
			return slot
	return {}

func hero_for_peer(peer_id: int) -> String:
	var s: Dictionary = slot_for_peer(peer_id)
	return String(s.get("hero_id", ""))

func snapshot() -> Array:
	# Returns a deep copy so listeners can render without holding a live
	# reference into the state.
	var out: Array = []
	for slot in slots:
		out.append(slot.duplicate())
	return out

func adopt_snapshot(snap: Array) -> void:
	# Client-side: replace local slots with a host-pushed snapshot.
	if snap == null:
		return
	for i in min(slots.size(), snap.size()):
		var src: Dictionary = snap[i]
		slots[i] = {
			"slot_index": int(src.get("slot_index", i)),
			"peer_id": int(src.get("peer_id", 0)),
			"hero_id": String(src.get("hero_id", "")),
			"ready": bool(src.get("ready", false)),
			"name": String(src.get("name", "")),
		}
	slots_changed.emit()
	ready_to_start_changed.emit(_is_ready_to_start())

# ── Static helpers ─────────────────────────────────────────────────────

static func generate_host_code(rng: RandomNumberGenerator) -> String:
	# Picks from a 31-char alphabet that excludes 0/O/1/I/L so dictation
	# over voice survives. RNG passed in so callers can use a seeded
	# generator if they want reproducible dev codes.
	var alpha: String = MultiplayerDataClass.HOST_CODE_ALPHABET
	var out := ""
	for i in MultiplayerDataClass.HOST_CODE_LENGTH:
		out += alpha.substr(rng.randi_range(0, alpha.length() - 1), 1)
	return out

# ── internals ─────────────────────────────────────────────────────────

func _is_ready_to_start() -> bool:
	# Need at least one filled slot, and every filled slot ready with a
	# hero locked. Solo-via-host (1 peer) is a valid start state.
	var any := false
	for slot in slots:
		if int(slot.peer_id) == 0:
			continue
		any = true
		if not bool(slot.ready):
			return false
		if String(slot.hero_id).is_empty():
			return false
	return any
