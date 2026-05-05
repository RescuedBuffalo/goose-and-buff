class_name InventorySystem extends RefCounted
##
## Pure 8-slot inventory + equipped weapon. Hot-bar grade — index 0..7
## are the inventory slots, plus a separate equipped-weapon slot.
##
## Operations are pure: they mutate the internal state and emit a signal
## describing what changed. Adapters subscribe to slot_changed /
## selected_changed / equipped_changed and re-render. They never read the
## arrays directly.
##
## Stack semantics: add(item_id, count) tries to top up an existing slot
## of the same item before claiming a new slot. Returns the leftover
## count that didn't fit (caller can drop a world pickup if non-zero).

const Items := preload("res://data/items.gd")

const SLOT_COUNT := 8

signal slot_changed(slot_index: int, slot: Dictionary)
signal selected_changed(slot_index: int)
signal equipped_changed(item_id: String)
signal inventory_changed()
signal added_item(item_id: String, count: int)

# Each slot is {item_id: String, count: int}. An empty slot is {item_id: "", count: 0}.
var slots: Array = []
var selected_index: int = 0
var equipped_weapon_id: String = "bare_hands"

func reset() -> void:
	slots = []
	for i in SLOT_COUNT:
		slots.append({"item_id": "", "count": 0})
	selected_index = 0
	equipped_weapon_id = "bare_hands"
	for i in SLOT_COUNT:
		slot_changed.emit(i, slots[i])
	selected_changed.emit(selected_index)
	equipped_changed.emit(equipped_weapon_id)
	inventory_changed.emit()

func add(item_id: String, count: int) -> int:
	# Returns leftover that didn't fit. Top up existing matching slots
	# first (in order), then claim empties. Stops returning leftover
	# only when count hits zero.
	if count <= 0 or item_id.is_empty():
		return 0
	var max_stack: int = Items.max_stack(item_id)
	var remaining := count
	# First pass: top up existing.
	for i in SLOT_COUNT:
		if remaining <= 0: break
		var slot: Dictionary = slots[i]
		if slot.item_id != item_id: continue
		var room: int = max_stack - int(slot.count)
		if room <= 0: continue
		var deposit: int = min(room, remaining)
		slot.count = int(slot.count) + deposit
		remaining -= deposit
		slot_changed.emit(i, slot)
	# Second pass: claim empties.
	for i in SLOT_COUNT:
		if remaining <= 0: break
		var slot: Dictionary = slots[i]
		if not slot.item_id.is_empty(): continue
		var deposit: int = min(max_stack, remaining)
		slot.item_id = item_id
		slot.count = deposit
		remaining -= deposit
		slot_changed.emit(i, slot)
	if remaining < count:
		added_item.emit(item_id, count - remaining)
		inventory_changed.emit()
	return remaining

func has_at_least(item_id: String, count: int) -> bool:
	if count <= 0:
		return true
	var total: int = 0
	for i in SLOT_COUNT:
		var slot: Dictionary = slots[i]
		if slot.item_id == item_id:
			total += int(slot.count)
			if total >= count:
				return true
	return false

func remove_item(item_id: String, count: int) -> bool:
	# Pull `count` of `item_id` from any combination of slots holding
	# it. Returns false (with no mutation) if the inventory doesn't have
	# enough to satisfy the request.
	if count <= 0:
		return true
	if not has_at_least(item_id, count):
		return false
	var remaining := count
	for i in SLOT_COUNT:
		if remaining <= 0: break
		var slot: Dictionary = slots[i]
		if slot.item_id != item_id: continue
		var take: int = min(int(slot.count), remaining)
		slot.count = int(slot.count) - take
		remaining -= take
		if int(slot.count) <= 0:
			slot.item_id = ""
			slot.count = 0
		slot_changed.emit(i, slot)
	inventory_changed.emit()
	return true

func remove_from_slot(idx: int, count: int) -> int:
	# Pulls up to `count` from a specific slot. Returns how much was
	# actually removed (could be less if the slot had fewer).
	if not _is_valid_index(idx) or count <= 0:
		return 0
	var slot: Dictionary = slots[idx]
	if slot.item_id.is_empty():
		return 0
	var taken: int = min(int(slot.count), count)
	slot.count = int(slot.count) - taken
	if int(slot.count) <= 0:
		slot.item_id = ""
		slot.count = 0
	slot_changed.emit(idx, slot)
	inventory_changed.emit()
	return taken

func select_slot(idx: int) -> void:
	if not _is_valid_index(idx):
		return
	# Always re-emit and re-equip even if idx == selected_index. The
	# selected slot's contents can change between selections (e.g. the
	# hand axe arriving in slot 0 *after* reset already set selection
	# to 0), and we want re-selection to pick that up.
	selected_index = idx
	selected_changed.emit(idx)
	var item_id: String = slots[idx].item_id
	if not item_id.is_empty() and Items.is_weapon(item_id):
		_set_equipped_from_item(item_id)

func clear_selection() -> void:
	# Right-click disarms whatever placeable was selected. Has to
	# actually mutate selected_index, not just emit -1 — build_overlay
	# polls selected_item_id() every frame, and that reads from
	# selected_index. Without the mutation, the ghost stays armed even
	# though the HUD shows no highlight. Hotkeys (1..8) re-arm normally.
	selected_index = -1
	selected_changed.emit(-1)

func selected_slot() -> Dictionary:
	if not _is_valid_index(selected_index):
		return {"item_id": "", "count": 0}
	return slots[selected_index]

func selected_item_id() -> String:
	return selected_slot().item_id

func equipped_weapon() -> String:
	return equipped_weapon_id

# ── internals ─────────────────────────────────────────────────────────

func _is_valid_index(idx: int) -> bool:
	return idx >= 0 and idx < SLOT_COUNT

func _set_equipped_from_item(item_id: String) -> void:
	var item: Dictionary = Items.get_item(item_id)
	var weapon_id: String = item.get("weapon_id", "bare_hands")
	if weapon_id == equipped_weapon_id:
		return
	equipped_weapon_id = weapon_id
	equipped_changed.emit(equipped_weapon_id)
