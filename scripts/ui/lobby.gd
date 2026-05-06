extends Control
##
## Lobby scene (BUF-150). Three slots, hero-select, host-code display
## or code-entry depending on whether the local peer is hosting or
## joining. Subscribes to MpIo for state and routes input back through
## MpIo.pick_hero / set_ready / light_the_lantern.
##
## Voice rules: sentence case, totem names only, "Light the lantern" as
## the start verb. No emoji. Slot copy reads "Goose has joined the watch"
## rather than "Player 2 connected".

const MultiplayerDataClass := preload("res://data/multiplayer.gd")
const Heroes := preload("res://data/heroes.gd")
const WorldGenerator := preload("res://scripts/logic/world_generator.gd")

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const RUN_START_PATH := "res://scenes/ui/run_start.tscn"

@onready var _title: Label = $Margin/V/Header/Title
@onready var _subtitle: Label = $Margin/V/Header/Subtitle
@onready var _host_code_label: Label = $Margin/V/CodeRow/HostCode
@onready var _join_code_input: LineEdit = $Margin/V/CodeRow/JoinCode
@onready var _join_address_input: LineEdit = $Margin/V/CodeRow/JoinAddress
@onready var _join_button: Button = $Margin/V/CodeRow/JoinButton
@onready var _host_button: Button = $Margin/V/CodeRow/HostButton
@onready var _slots_box: VBoxContainer = $Margin/V/Slots
@onready var _hero_row: HBoxContainer = $Margin/V/HeroRow
@onready var _ready_button: Button = $Margin/V/Footer/ReadyButton
@onready var _start_button: Button = $Margin/V/Footer/StartButton
@onready var _back_button: Button = $Margin/V/Footer/BackButton
@onready var _status_label: Label = $Margin/V/StatusLabel

var _selected_hero: String = ""

func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	for child in _hero_row.get_children():
		if child is Button:
			var hero_id: String = String(child.name)
			(child as Button).pressed.connect(_on_hero_pressed.bind(hero_id))
	MpIo.lobby_updated.connect(_refresh)
	MpIo.hosted.connect(_on_hosted)
	MpIo.joined.connect(_on_joined)
	MpIo.join_failed.connect(_on_join_failed)
	MpIo.peer_state_changed.connect(_on_peer_state_changed)
	MpIo.run_started.connect(_on_run_started)
	# If MpIo already has a peer (e.g. we returned from a previous lobby
	# without leaving), refresh into that state. Otherwise show the host /
	# join entry surface.
	_refresh()

func _on_host_pressed() -> void:
	if MpIo.is_multiplayer():
		return
	if MpIo.host("Host"):
		_status_label.text = "Hosting. Share the code with your watch."
	else:
		_status_label.text = "Could not open the lantern. Try again."

func _on_join_pressed() -> void:
	if MpIo.is_multiplayer():
		return
	var address: String = _join_address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var code: String = _join_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_status_label.text = "Enter the code your host gave you."
		return
	_status_label.text = "Finding the lantern…"
	MpIo.join(address, code, "Joiner")

func _on_hero_pressed(hero_id: String) -> void:
	_selected_hero = hero_id
	if MpIo.is_multiplayer():
		MpIo.pick_hero(hero_id)
	_refresh()

func _on_ready_pressed() -> void:
	if not MpIo.is_multiplayer():
		return
	# Toggle ready off the slot's current state so the same button serves
	# "lock in" and "unlock".
	var slot: Dictionary = MpIo.lobby.slot_for_peer(MpIo.local_peer_id)
	var current_ready: bool = bool(slot.get("ready", false))
	MpIo.set_ready(not current_ready)

func _on_start_pressed() -> void:
	if not MpIo.is_host():
		return
	if not MpIo.lobby.is_ready_to_start():
		_status_label.text = "Wait for every hero to lock in."
		return
	var seed_int: int = WorldGenerator.random_seed()
	MpIo.light_the_lantern(seed_int)

func _on_back_pressed() -> void:
	MpIo.leave()
	get_tree().change_scene_to_file(RUN_START_PATH)

func _on_hosted(code: String) -> void:
	_host_code_label.text = "Code: %s" % code
	_host_code_label.visible = true
	_join_code_input.visible = false
	_join_address_input.visible = false
	_join_button.visible = false
	_host_button.visible = false
	_status_label.text = "Hosting. Share the code with your watch."
	_refresh()

func _on_joined(_peer_id: int) -> void:
	_host_code_label.text = "Joined the watch."
	_host_code_label.visible = true
	_join_code_input.visible = false
	_join_address_input.visible = false
	_join_button.visible = false
	_host_button.visible = false
	_status_label.text = "Joined. Pick your totem."
	_refresh()

func _on_join_failed(reason: String) -> void:
	_status_label.text = "Could not find the lantern (%s). Check the address." % reason

func _on_peer_state_changed(_peer_id: int, _state_id: String, _hero_id: String) -> void:
	_refresh()

func _on_run_started(_seed: int, _assignments: Dictionary) -> void:
	# Every peer (host + clients) gets this. Transition to main.tscn.
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _refresh() -> void:
	# Render slot rows + hero buttons + footer state.
	for child in _slots_box.get_children():
		child.queue_free()
	if MpIo.is_multiplayer():
		_title.text = "The watch gathers"
		_subtitle.text = "Three totems, three slots. Pick yours, lock in, light the lantern."
		var slots: Array = MpIo.lobby.snapshot()
		for slot in slots:
			_slots_box.add_child(_make_slot_row(slot))
		var locked_heroes: Dictionary = {}
		for slot in slots:
			if int(slot.peer_id) != 0 and not String(slot.hero_id).is_empty():
				locked_heroes[String(slot.hero_id)] = int(slot.peer_id)
		for child in _hero_row.get_children():
			if child is Button:
				var hero_id: String = String(child.name)
				var btn: Button = child as Button
				btn.button_pressed = (_selected_hero == hero_id)
				# Disable buttons for heroes another peer has locked.
				var owner: int = int(locked_heroes.get(hero_id, 0))
				btn.disabled = owner != 0 and owner != MpIo.local_peer_id
				btn.toggle_mode = true
		var local_slot: Dictionary = MpIo.lobby.slot_for_peer(MpIo.local_peer_id)
		var has_hero: bool = not String(local_slot.get("hero_id", "")).is_empty()
		_ready_button.visible = true
		_ready_button.disabled = not has_hero
		_ready_button.text = "Unlock" if bool(local_slot.get("ready", false)) else "Lock in"
		_start_button.visible = MpIo.is_host()
		_start_button.disabled = not MpIo.lobby.is_ready_to_start()
	else:
		_title.text = "Light a lantern, or follow one"
		_subtitle.text = "Host the watch and share the code, or join with a code from your host."
		_ready_button.visible = false
		_start_button.visible = false
		_join_code_input.visible = true
		_join_address_input.visible = true
		_join_button.visible = true
		_host_button.visible = true
		_host_code_label.visible = false

func _make_slot_row(slot: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	var pid: int = int(slot.peer_id)
	var hero_id: String = String(slot.hero_id)
	var slot_index: int = int(slot.slot_index)
	if pid == 0:
		label.text = "Slot %d — empty" % (slot_index + 1)
		label.modulate = DesignTokens.FG_3
	elif hero_id.is_empty():
		label.text = "Slot %d — choosing a totem" % (slot_index + 1)
		label.modulate = DesignTokens.FG_2
	else:
		var ready_marker: String = " — locked in" if bool(slot.ready) else " — choosing"
		label.text = "Slot %d — %s%s" % [slot_index + 1, hero_id, ready_marker]
		label.modulate = DesignTokens.PARCHMENT_0
	label.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	row.add_child(label)
	return row
