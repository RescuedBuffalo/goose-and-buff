extends Control
##
## Lodge hub — the warm interior the player returns to between runs (BUF-142).
##
## Reads cross-run state from the SaveIo autoload: surfaces the last run's
## stats, lists the last MAX_RUNS runs, renders the lodge's accumulated
## artifacts (BUF-130), surfaces the embers balance + upgrade tree
## (BUF-147 / BUF-148), and offers a "Run again" button that boots the
## run-start screen (BUF-145) so the player picks a hero + optional seed.
##
## The Variants panel still ships as a visible placeholder — it holds
## layout space until BUF-129 lands.
##
## All visible strings follow the voice rules: sentence case, no emoji,
## tabular numerals on counts, "watches stood/broke" rather than wins/losses.

const SaveStateClass := preload("res://scripts/logic/save_state.gd")
const ArtifactsData := preload("res://data/lodge_artifacts.gd")
const UpgradeTreeScript := preload("res://scripts/ui/upgrade_tree.gd")
const WorldGenerator := preload("res://scripts/logic/world_generator.gd")

const RUN_START_SCENE_PATH := "res://scenes/ui/run_start.tscn"

@onready var _last_outcome: Label = $Margin/Scroll/V/LastWatch/Outcome
@onready var _last_subtitle: Label = $Margin/Scroll/V/LastWatch/Subtitle
@onready var _last_stats: Label = $Margin/Scroll/V/LastWatch/Stats
@onready var _last_empty: Label = $Margin/Scroll/V/LastWatch/Empty
@onready var _embers_balance: Label = $Margin/Scroll/V/EmbersPanel/EmbersRow/Balance
@onready var _upgrade_tree_mount: Control = $Margin/Scroll/V/UpgradeSection/UpgradeTreeMount
@onready var _artifacts_empty: Label = $Margin/Scroll/V/Reserved/Artifacts/V/Empty
@onready var _artifacts_scroll: ScrollContainer = $Margin/Scroll/V/Reserved/Artifacts/V/Scroll
@onready var _artifacts_list: VBoxContainer = $Margin/Scroll/V/Reserved/Artifacts/V/Scroll/List
@onready var _history_list: VBoxContainer = $Margin/Scroll/V/History/List
@onready var _history_empty: Label = $Margin/Scroll/V/History/Empty
@onready var _run_again: Button = $Margin/Scroll/V/Footer/RunAgain

var _upgrade_tree: Control = null

func _ready() -> void:
	_run_again.pressed.connect(_on_run_again_pressed)
	_mount_upgrade_tree()
	_render()

func _mount_upgrade_tree() -> void:
	if _upgrade_tree_mount == null:
		return
	_upgrade_tree = UpgradeTreeScript.new()
	_upgrade_tree.size = _upgrade_tree_mount.size
	_upgrade_tree.anchor_right = 1.0
	_upgrade_tree.anchor_bottom = 1.0
	_upgrade_tree.purchased.connect(_on_upgrade_purchased)
	_upgrade_tree_mount.add_child(_upgrade_tree)

func _render() -> void:
	_render_embers()
	var last: Dictionary = SaveIo.last_run()
	if last.is_empty():
		_last_outcome.visible = false
		_last_subtitle.visible = false
		_last_stats.visible = false
		_last_empty.visible = true
	else:
		_last_outcome.visible = true
		_last_subtitle.visible = true
		_last_stats.visible = true
		_last_empty.visible = false
		_last_outcome.text = _outcome_headline(last)
		_last_subtitle.text = _outcome_subtitle(last)
		_last_stats.text = _format_stats(last)
	_render_artifacts()
	_render_history()

func _render_embers() -> void:
	if _embers_balance == null:
		return
	# Tabular numeral with a trailing "ember(s)" hint kept in the eyebrow
	# so the headline number stays scannable. Voice rule: sentence case
	# in the eyebrow, plain integer here.
	_embers_balance.text = str(SaveIo.embers())

func _render_artifacts() -> void:
	# Lodge accumulates across runs (BUF-130). Group acquired artifacts by
	# their assigned spot so the panel reads as a room — entrance first,
	# fixtures last — rather than a flat list. Hover surfaces flavor;
	# nothing here ever explains.
	#
	# The list lives inside a ScrollContainer because the lodge "only
	# accumulates" — a long campaign would otherwise grow the panel until
	# it pushed History and Footer out of the viewport.
	for child in _artifacts_list.get_children():
		child.queue_free()
	var acquired: Array = SaveIo.artifacts()
	if acquired.is_empty():
		_artifacts_empty.visible = true
		_artifacts_scroll.visible = false
		return
	_artifacts_empty.visible = false
	_artifacts_scroll.visible = true
	var by_spot := _group_artifacts_by_spot(acquired)
	for spot in ArtifactsData.SPOT_ORDER:
		var entries: Array = by_spot.get(spot, [])
		if entries.is_empty():
			continue
		_artifacts_list.add_child(_make_spot_header(spot))
		for entry in entries:
			_artifacts_list.add_child(_make_artifact_row(entry))

func _group_artifacts_by_spot(acquired: Array) -> Dictionary:
	# Acquisition order is preserved within each spot — the lodge fills up
	# in the order watches end, just clustered by where things land.
	var grouped := {}
	for record in acquired:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var artifact_id := String(record.get("id", ""))
		var entry: Dictionary = ArtifactsData.get_artifact(artifact_id)
		if entry.is_empty():
			# Save schema kept the id but the pool no longer recognizes it.
			# Drop silently — better than rendering an empty row.
			continue
		var spot := String(entry.get("spot", ""))
		if not grouped.has(spot):
			grouped[spot] = []
		(grouped[spot] as Array).append(entry)
	return grouped

func _make_spot_header(spot: String) -> Label:
	var header := Label.new()
	header.text = String(ArtifactsData.SPOT_LABEL.get(spot, spot))
	header.add_theme_color_override("font_color", DesignTokens.FG_2)
	header.add_theme_font_size_override("font_size", DesignTokens.FS_XS)
	return header

func _make_artifact_row(entry: Dictionary) -> Control:
	# A label per artifact. tooltip_text shows the flavor on hover —
	# inspectable per the spec, never expanded into an explanation. The
	# mouse_filter override is required because Label defaults to IGNORE
	# in Godot 4, which suppresses the tooltip.
	var row := Label.new()
	row.text = String(entry.get("name", ""))
	row.tooltip_text = String(entry.get("flavor", ""))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_color_override("font_color", DesignTokens.PARCHMENT_INK)
	row.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	return row

func _render_history() -> void:
	for child in _history_list.get_children():
		child.queue_free()
	var rs: Array = SaveIo.runs()
	if rs.is_empty():
		_history_empty.visible = true
		return
	_history_empty.visible = false
	for r in rs:
		_history_list.add_child(_make_history_row(r))

func _make_history_row(r: Dictionary) -> Label:
	var row := Label.new()
	row.text = _format_history_line(r)
	row.add_theme_color_override("font_color", DesignTokens.FG_2)
	row.add_theme_font_size_override("font_size", DesignTokens.FS_SM)
	return row

# ── Voice-rule formatters ───────────────────────────────────────────────

func _outcome_headline(r: Dictionary) -> String:
	# Sentence case. Avoid "death" / "fail" framing per voice rules.
	if String(r.get("outcome", "")) == SaveStateClass.OUTCOME_VICTORY:
		return "We held until spring."
	return "The watch broke."

func _outcome_subtitle(r: Dictionary) -> String:
	var nights := int(r.get("nights_survived", 0))
	if String(r.get("outcome", "")) == SaveStateClass.OUTCOME_VICTORY:
		return "Three nights stood. The lodge still stands."
	if nights == 0:
		return "No watches stood. We try again."
	if nights == 1:
		return "One watch stood. Then the line broke."
	return "%d watches stood. Then the line broke." % nights

func _format_stats(r: Dictionary) -> String:
	# Tabular numerals — single line, separator middots match the existing
	# end-screen voice. "Nights" framing kept since the verb tense ("we
	# survived") tells the player how to read it.
	#
	# Seed appended at the end so the player can recover the watch
	# seed from the lodge after the end-screen auto-transition closes.
	# Older v1 saves don't carry a seed; show only when a non-zero
	# value is present.
	var line: String = "Nights survived: %d  ·  resources gathered: %d  ·  enemies felled: %d  ·  run time: %s" % [
		int(r.get("nights_survived", 0)),
		int(r.get("resources_gathered", 0)),
		int(r.get("enemies_felled", 0)),
		_format_duration(float(r.get("duration_seconds", 0.0))),
	]
	var seed_int: int = int(r.get("seed", 0))
	if seed_int != 0:
		line += "  ·  watch seed " + WorldGenerator.seed_to_string(seed_int)
	return line

func _format_history_line(r: Dictionary) -> String:
	var outcome_word := "Held" if String(r.get("outcome", "")) == SaveStateClass.OUTCOME_VICTORY else "Broke"
	return "%s  ·  %s  ·  nights %d  ·  felled %d  ·  %s" % [
		outcome_word,
		String(r.get("hero_id", "—")),
		int(r.get("nights_survived", 0)),
		int(r.get("enemies_felled", 0)),
		_format_duration(float(r.get("duration_seconds", 0.0))),
	]

func _format_duration(seconds: float) -> String:
	# Voice rule: timers as `0:24`, never `24s`.
	var total := int(round(seconds))
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]

# ── Actions ─────────────────────────────────────────────────────────────

func _on_run_again_pressed() -> void:
	# M2 (BUF-145): runs go through the run-start screen first so the
	# player can pick a totem + optional seed. The screen swaps to
	# main.tscn once they confirm.
	get_tree().change_scene_to_file(RUN_START_SCENE_PATH)

func _on_upgrade_purchased(_upgrade_id: String) -> void:
	# Refresh the embers balance + tree visual states. The tree's own
	# _render() runs internally on confirm; we re-render the embers
	# pill here so the balance pill isn't stale.
	_render_embers()
