extends Control
##
## Lodge hub — the warm interior the player returns to between runs (BUF-142).
##
## Reads cross-run state from the SaveIo autoload: surfaces the last run's
## stats, lists the last MAX_RUNS runs, and offers a "Run again" button
## that boots a fresh run.
##
## Reserved UI surfaces (kept as visible placeholder panels) hold space
## for Lodge artifacts (BUF-130) and hero variants (BUF-129) so when those
## ship the layout doesn't shift.
##
## All visible strings follow the voice rules: sentence case, no emoji,
## tabular numerals on counts, "watches stood/broke" rather than wins/losses.

const SaveStateClass := preload("res://scripts/logic/save_state.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

@onready var _last_outcome: Label = $Margin/V/LastWatch/Outcome
@onready var _last_subtitle: Label = $Margin/V/LastWatch/Subtitle
@onready var _last_stats: Label = $Margin/V/LastWatch/Stats
@onready var _last_empty: Label = $Margin/V/LastWatch/Empty
@onready var _history_list: VBoxContainer = $Margin/V/History/List
@onready var _history_empty: Label = $Margin/V/History/Empty
@onready var _run_again: Button = $Margin/V/Footer/RunAgain

func _ready() -> void:
	_run_again.pressed.connect(_on_run_again_pressed)
	_render()

func _render() -> void:
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
	_render_history()

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
	# "Watches stood" — recasts the loss without naming it as a fail count.
	if nights == 0:
		return "No watches stood. We try again."
	if nights == 1:
		return "One watch stood. Then the line broke."
	return "%d watches stood. Then the line broke." % nights

func _format_stats(r: Dictionary) -> String:
	# Tabular numerals — single line, separator middots match the existing
	# end-screen voice. "Nights" framing kept since the verb tense ("we
	# survived") tells the player how to read it.
	return "Nights survived: %d  ·  resources gathered: %d  ·  enemies felled: %d  ·  run time: %s" % [
		int(r.get("nights_survived", 0)),
		int(r.get("resources_gathered", 0)),
		int(r.get("enemies_felled", 0)),
		_format_duration(float(r.get("duration_seconds", 0.0))),
	]

func _format_history_line(r: Dictionary) -> String:
	# One line per past run. Outcome word first so the eye scans the
	# column for "held / broke" patterns.
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
	# Hero selector is BUF-129's territory; until then "Run again" goes
	# straight back into the run. When the selector lands, swap this to
	# load that scene instead — the lodge contract here is unchanged.
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
