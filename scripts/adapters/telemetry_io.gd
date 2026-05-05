extends Node
##
## Telemetry persistence adapter. Subscribes to a Telemetry instance's
## event_logged signal, buffers events in memory, and flushes them to
## `user://telemetry/<run_id>.jsonl` on a background thread.
##
## The hot path (signal callback) only does a mutex-guarded append — no
## file I/O. A worker thread wakes on a semaphore (periodic tick from
## _process or an explicit run_end) and drains the buffer to disk.
##
## File format is newline-delimited JSON ("jsonl"): one event per line.
## Append-friendly, line-grain crash-safe, trivial to load offline.

const TELEMETRY_DIR := "user://telemetry"
const FLUSH_INTERVAL_SEC := 2.0

var _telemetry: Telemetry = null
var _buffer: Array = []
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _thread: Thread = null
var _running: bool = false
var _flush_accum: float = 0.0

func attach(t: Telemetry) -> void:
	_telemetry = t
	_telemetry.event_logged.connect(_on_event_logged)
	DirAccess.make_dir_recursive_absolute(TELEMETRY_DIR)
	_running = true
	_thread = Thread.new()
	_thread.start(_writer_loop)

func _on_event_logged(event: Dictionary) -> void:
	_mutex.lock()
	_buffer.append(event)
	_mutex.unlock()
	# run_end is the one event we want on disk before the player closes
	# the game — wake the writer immediately rather than waiting for the
	# periodic flush.
	if event.get("kind", "") == Telemetry.KIND_RUN_END:
		_semaphore.post()

func _process(delta: float) -> void:
	_flush_accum += delta
	if _flush_accum >= FLUSH_INTERVAL_SEC:
		_flush_accum = 0.0
		_semaphore.post()

func _exit_tree() -> void:
	_running = false
	_semaphore.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	# One last drain on the main thread for any events posted between
	# the worker's last wake and shutdown.
	_drain_to_disk()

# ── Worker ────────────────────────────────────────────────────────────

func _writer_loop() -> void:
	while true:
		_semaphore.wait()
		if not _running:
			return
		_drain_to_disk()

func _drain_to_disk() -> void:
	_mutex.lock()
	var pending: Array = _buffer.duplicate()
	_buffer.clear()
	_mutex.unlock()
	if pending.is_empty():
		return
	# Group by run_id so each flush touches at most one file per run.
	# In practice all events in a flush share a run_id, but grouping
	# keeps the contract honest if a run_end and a run_start straddle.
	var by_run: Dictionary = {}
	for ev in pending:
		var rid: String = String(ev.get("run_id", ""))
		if rid.is_empty():
			continue
		if not by_run.has(rid):
			by_run[rid] = []
		by_run[rid].append(ev)
	for rid in by_run:
		_append_events(rid, by_run[rid])

func _append_events(run_id: String, events: Array) -> void:
	var path := "%s/%s.jsonl" % [TELEMETRY_DIR, run_id]
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Telemetry: unable to open %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	for ev in events:
		f.store_line(JSON.stringify(ev))
	f.close()
