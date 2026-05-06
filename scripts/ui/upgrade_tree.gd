extends Control
##
## Lodge upgrade tree (BUF-148). Per-hero tabs (Buffalo / Goose / Fox /
## Shared) with a column-per-tier tree visualization. Owned upgrades
## glow in their faction's lantern color; available upgrades read warm-
## parchment; locked (prereq missing) read dim. Clicking an available
## upgrade pops a "Light this ember?" confirm with effect summary +
## cost, then commits via SaveIo.purchase_upgrade.
##
## Visual states use design tokens — no hardcoded colors.
##
## Mounted by lodge.gd via add_child into the UpgradeTreeMount Control.
## The tree size_flags fill the parent so the layout stays responsive.

const Upgrades := preload("res://data/upgrades.gd")
const StatSystemClass := preload("res://scripts/logic/stat_system.gd")

signal purchased(upgrade_id: String)

const TAB_HEIGHT := 36.0
const NODE_W := 220.0
const NODE_H := 96.0
const COL_GAP := 36.0
const ROW_GAP := 16.0

var _tabs_box: HBoxContainer
var _content: Control
var _active_dialog: ConfirmationDialog = null
var _selected_tab: String = "Shared"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Fixed minimum size — tree content is column-laid-out at known
	# coordinates, so a deterministic frame keeps the lodge ScrollContainer
	# aware of how much room the section needs.
	custom_minimum_size = Vector2(1080, 720)
	_tabs_box = HBoxContainer.new()
	_tabs_box.position = Vector2(0, 0)
	_tabs_box.size = Vector2(1080, TAB_HEIGHT)
	_tabs_box.add_theme_constant_override("separation", 12)
	add_child(_tabs_box)
	_content = Control.new()
	_content.position = Vector2(0, TAB_HEIGHT + 8)
	_content.size = Vector2(1080, 680)
	add_child(_content)
	_build_tabs()
	# Default tab — start on the player's last hero if one is selected,
	# otherwise the Shared track.
	var preferred: String = GameState.hero_id
	if not preferred.is_empty() and Upgrades.hero_tabs().has(preferred):
		_selected_tab = preferred
	_render()

func _build_tabs() -> void:
	for hero in Upgrades.hero_tabs():
		var btn := Button.new()
		btn.text = hero
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(140, TAB_HEIGHT)
		btn.pressed.connect(_on_tab_picked.bind(hero))
		_tabs_box.add_child(btn)

func _on_tab_picked(hero: String) -> void:
	_selected_tab = hero
	_render()

func _render() -> void:
	# Re-render is cheap (~20 nodes); just nuke and rebuild the content
	# control's children. No tweens — instant tab swap reads as confident.
	for c in _content.get_children():
		c.queue_free()
	# Tab pressed-state mirror.
	for i in _tabs_box.get_child_count():
		var b := _tabs_box.get_child(i) as Button
		if b == null:
			continue
		b.button_pressed = b.text == _selected_tab
	# Pick the upgrade list for the active tab.
	var list: Array
	if _selected_tab == Upgrades.HERO_SHARED:
		list = Upgrades.shared_upgrades()
	else:
		list = Upgrades.for_hero_only(_selected_tab)
	# Layout: column per tier (1, 2, 3). Within each column, stack rows.
	var columns: Dictionary = {1: [], 2: [], 3: []}
	for u in list:
		var t: int = int(u.tier)
		columns[t].append(u)
	# Tier headers + nodes.
	var owned: Array = SaveIo.owned_upgrades()
	var embers: int = SaveIo.embers()
	var node_positions: Dictionary = {}  # upgrade_id → Vector2 center
	for tier in [1, 2, 3]:
		var col_x: float = (tier - 1) * (NODE_W + COL_GAP) + 16
		var header := Label.new()
		header.text = "Tier %d" % tier
		header.add_theme_color_override("font_color", DesignTokens.PARCHMENT_INK)
		header.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
		header.position = Vector2(col_x, 0)
		header.size = Vector2(NODE_W, 22)
		_content.add_child(header)
		var entries: Array = columns[tier]
		for i in entries.size():
			var u: Dictionary = entries[i]
			var y: float = 28 + i * (NODE_H + ROW_GAP)
			var card := _make_upgrade_card(u, owned, embers)
			card.position = Vector2(col_x, y)
			card.size = Vector2(NODE_W, NODE_H)
			_content.add_child(card)
			node_positions[String(u.id)] = card.position + card.size * 0.5
	# Prereq lines drawn via a single Control with custom _draw —
	# attached after node positions are known so _draw can read them.
	var lines := _LineLayer.new()
	lines.connections = _build_connection_specs(list, owned, node_positions)
	lines.size = _content.size
	_content.add_child(lines)
	lines.move_to_front()
	# lodge.gd re-renders the Embers balance via the purchased signal.

func _build_connection_specs(list: Array, owned: Array, node_positions: Dictionary) -> Array:
	var specs: Array = []
	for u in list:
		var prereq: String = String(u.get("prereq", ""))
		if prereq.is_empty():
			continue
		if not node_positions.has(String(u.id)) or not node_positions.has(prereq):
			continue
		var p_a: Vector2 = node_positions[prereq]
		var p_b: Vector2 = node_positions[String(u.id)]
		var prereq_owned: bool = owned.has(prereq)
		specs.append({"from": p_a, "to": p_b, "owned": prereq_owned})
	return specs

func _make_upgrade_card(u: Dictionary, owned: Array, embers: int) -> Control:
	var state: String = _state_for(u, owned, embers)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Style the panel via a per-state stylebox so owned/available/locked
	# read clearly. We build the styleboxes here so design tokens flow
	# through without needing a theme resource on disk yet.
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	match state:
		"owned":
			sb.bg_color = DesignTokens.PARCHMENT_1
			sb.border_color = DesignTokens.core_color(String(u.hero) if String(u.hero) != "Shared" else "Buffalo")
		"available":
			sb.bg_color = DesignTokens.PARCHMENT_0
			sb.border_color = DesignTokens.PARCHMENT_2
		"insufficient":
			sb.bg_color = DesignTokens.PARCHMENT_1
			sb.border_color = DesignTokens.HP_WARN
		_:  # locked
			sb.bg_color = Color(DesignTokens.PARCHMENT_2.r, DesignTokens.PARCHMENT_2.g, DesignTokens.PARCHMENT_2.b, 0.45)
			sb.border_color = Color(DesignTokens.PARCHMENT_2.r, DesignTokens.PARCHMENT_2.g, DesignTokens.PARCHMENT_2.b, 0.6)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var name_label := Label.new()
	name_label.text = String(u.display_name)
	name_label.add_theme_color_override("font_color", DesignTokens.PARCHMENT_INK)
	name_label.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	v.add_child(name_label)
	var desc := Label.new()
	desc.text = String(u.description)
	desc.add_theme_color_override("font_color", Color(0.317, 0.243, 0.18, 1.0))
	desc.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(desc)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(bottom)
	var cost := Label.new()
	cost.text = "%d ember%s" % [int(u.cost), "" if int(u.cost) == 1 else "s"]
	cost.add_theme_color_override("font_color", DesignTokens.PARCHMENT_INK)
	cost.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	bottom.add_child(cost)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var action := Button.new()
	action.custom_minimum_size = Vector2(80, 28)
	match state:
		"owned":
			action.text = "Owned"
			action.disabled = true
		"available":
			action.text = "Light"
			action.pressed.connect(_on_light_pressed.bind(String(u.id)))
		"insufficient":
			action.text = "Need more"
			action.disabled = true
		_:
			action.text = "Locked"
			action.disabled = true
	bottom.add_child(action)
	return panel

func _state_for(u: Dictionary, owned: Array, embers: int) -> String:
	if owned.has(String(u.id)):
		return "owned"
	var prereq: String = String(u.get("prereq", ""))
	if not prereq.is_empty() and not owned.has(prereq):
		return "locked"
	if embers < int(u.cost):
		return "insufficient"
	return "available"

# ── Confirm flow ─────────────────────────────────────────────────────

func _on_light_pressed(upgrade_id: String) -> void:
	var u: Dictionary = Upgrades.by_id(upgrade_id)
	if u.is_empty():
		return
	_show_confirm(u)

func _show_confirm(u: Dictionary) -> void:
	# Bail if a dialog is already open — rapid double-clicking the
	# Light button would otherwise stack two dialogs on top of each
	# other, with the older one trapped underneath the newer modal.
	if _active_dialog != null and is_instance_valid(_active_dialog):
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Light this ember?"
	dialog.dialog_text = "%s\n\n%s\n\nCost: %d ember%s." % [
		String(u.display_name),
		String(u.description),
		int(u.cost),
		"" if int(u.cost) == 1 else "s",
	]
	dialog.ok_button_text = "Light"
	dialog.cancel_button_text = "Not yet"
	add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_confirmed.bind(String(u.id), dialog))
	dialog.canceled.connect(func(): _on_dialog_dismissed(dialog))
	dialog.popup_centered()

func _on_confirmed(upgrade_id: String, dialog: AcceptDialog) -> void:
	var result: Dictionary = SaveIo.purchase_upgrade(upgrade_id)
	if result.ok:
		purchased.emit(upgrade_id)
	_on_dialog_dismissed(dialog)
	_render()

func _on_dialog_dismissed(dialog: AcceptDialog) -> void:
	# Single cleanup point for both confirm + cancel paths so the
	# _active_dialog gate clears on either outcome. Without this the
	# gate would stick "open" after a cancel and block the next purchase
	# until something else cleared it.
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()
	if _active_dialog == dialog:
		_active_dialog = null


# ── Inner: connection-line layer ─────────────────────────────────────
class _LineLayer extends Control:
	var connections: Array = []  # [{from: Vector2, to: Vector2, owned: bool}]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for spec in connections:
			var color: Color = (
				DesignTokens.PARCHMENT_INK
				if bool(spec.owned)
				else Color(DesignTokens.PARCHMENT_2.r, DesignTokens.PARCHMENT_2.g, DesignTokens.PARCHMENT_2.b, 0.7)
			)
			# Dashed-look line: draw a series of short segments with gaps.
			var from_v: Vector2 = spec.from
			var to_v: Vector2 = spec.to
			var dist: float = from_v.distance_to(to_v)
			if dist <= 0.0:
				continue
			var dir: Vector2 = (to_v - from_v) / dist
			var step: float = 8.0
			var t: float = 0.0
			while t < dist:
				var a: Vector2 = from_v + dir * t
				var b: Vector2 = from_v + dir * min(dist, t + step * 0.6)
				draw_line(a, b, color, 2.0)
				t += step
