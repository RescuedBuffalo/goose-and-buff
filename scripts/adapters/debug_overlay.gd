extends Node2D
##
## Debug overlay (BUF-145). F3 toggles a layer that draws chunk
## boundaries, biome tags, and a small panel showing the seed,
## day_index, and chunk distribution. Lives in world space so it
## y-sorts with the tile layer and follows the camera.
##
## Two console commands are exposed via main.gd's keybindings, not via
## a real console:
##   regen_world(seed?) — regenerates the world (any seed, or random)
##   dump_world()       — writes the current WorldDef to user://debug/
##
## The brief leaves this gate-free for now ("we're three friends; nobody
## is shipping this to production"). Toggle via F3 even in a build.

const Sectors := preload("res://data/sectors.gd")
const Chunks := preload("res://data/chunks.gd")
const WorldGeneratorClass := preload("res://scripts/logic/world_generator.gd")
const StatSystemTest := preload("res://scripts/tests/stat_system_test.gd")

# Where dump_world() writes the WorldDef JSON.
const DEBUG_DUMP_DIR := "user://debug"

var sector: Node = null
var visible_overlay: bool = false
var world_def: Dictionary = {}

func attach(sector_ref: Node) -> void:
	sector = sector_ref

func set_world(def: Dictionary) -> void:
	world_def = def
	queue_redraw()

func toggle() -> void:
	visible_overlay = not visible_overlay
	queue_redraw()

func _draw() -> void:
	if not visible_overlay or sector == null or world_def.is_empty():
		return
	# Chunk boundaries — outline each 5x5 chunk in the player's hero color.
	var chunks: Array = world_def.get("chunks", [])
	for entry in chunks:
		var cpos: Vector2i = entry.chunk_pos
		var origin_tile := Vector2i(cpos.x * Chunks.CHUNK_SIZE, cpos.y * Chunks.CHUNK_SIZE)
		# Sector is typed as `Node` so `:=` can't infer the return type
		# of tile_to_world. Annotate explicitly so the parser is happy.
		var top: Vector2 = sector.tile_to_world(origin_tile)
		var right: Vector2 = sector.tile_to_world(origin_tile + Vector2i(Chunks.CHUNK_SIZE, 0))
		var bottom: Vector2 = sector.tile_to_world(origin_tile + Vector2i(Chunks.CHUNK_SIZE, Chunks.CHUNK_SIZE))
		var left: Vector2 = sector.tile_to_world(origin_tile + Vector2i(0, Chunks.CHUNK_SIZE))
		# Chunk color: temperate=warm, frosted=cool, frozen=ice. Easy
		# to scan at a glance which climate landed where.
		var color: Color = _color_for_climate(String(entry.climate))
		draw_polyline(PackedVector2Array([top, right, bottom, left, top]), color, 2.0, true)
		# Template id label at the chunk's center tile.
		var center_tile := origin_tile + Vector2i(Chunks.CHUNK_SIZE / 2, Chunks.CHUNK_SIZE / 2)
		var center_world: Vector2 = sector.tile_to_world(center_tile)
		var font: Font = ThemeDB.fallback_font
		var label: String = String(entry.template_id)
		draw_string(font, center_world + Vector2(-40, 4), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func _color_for_climate(climate: String) -> Color:
	match climate:
		"temperate": return Color(1.0, 0.85, 0.55, 0.85)
		"frosted":   return Color(0.7, 0.85, 1.0, 0.85)
		"frozen":    return Color(0.7, 0.95, 1.0, 0.95)
		_:           return Color(1.0, 1.0, 1.0, 0.6)

# ── F4: WorldDef dump for offline inspection ─────────────────────────

func dump_world(run_seed: int) -> void:
	if world_def.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DEBUG_DUMP_DIR)
	var seed_str: String = WorldGeneratorClass.seed_to_string(run_seed)
	var path: String = "%s/world_%s.json" % [DEBUG_DUMP_DIR, seed_str]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("debug: could not open %s" % path)
		return
	# Vector2i / Vector2 don't json natively — flatten into [x, y] pairs.
	f.store_string(JSON.stringify(_flatten_for_json(world_def), "\t"))
	f.close()
	print("debug: wrote ", path)

func handle_debug_key(event: InputEventKey) -> bool:
	# Returns true if the key was a debug command. Centralizes F5/F6/F12
	# QA hooks alongside F3/F4 so main.gd stays a coordinator. F3/F4
	# are still handled inline in main since they need the debug_panel
	# toggle and the run_seed.
	if not event.pressed:
		return false
	match event.keycode:
		KEY_F5:
			var balance: int = SaveIo.debug_grant_embers(5)
			print("debug: granted 5 embers (balance=%d)" % balance)
			return true
		KEY_F6:
			if event.shift_pressed:
				SaveIo.debug_clear_progression()
				print("debug: cleared embers + owned upgrades")
			else:
				var n: int = SaveIo.debug_grant_all_upgrades()
				print("debug: granted all upgrades (%d owned)" % n)
			return true
		KEY_F12:
			var report: Dictionary = StatSystemTest.run_all()
			StatSystemTest.print_results(report)
			return true
	return false

func _flatten_for_json(def: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for k in def.keys():
		var v = def[k]
		if v is Vector2i:
			copy[k] = [v.x, v.y]
		elif typeof(v) == TYPE_ARRAY and not (v as Array).is_empty() and (v as Array)[0] is Vector2i:
			var pts: Array = []
			for p in v:
				pts.append([p.x, p.y])
			copy[k] = pts
		elif k == "tiles":
			# Tile dicts pass through cleanly.
			copy[k] = v
		elif k == "resources":
			var rs: Array = []
			for r in v:
				rs.append({"kind": String(r.kind), "tile": [r.tile.x, r.tile.y]})
			copy[k] = rs
		elif k == "chunks":
			var cs: Array = []
			for c in v:
				cs.append({"chunk_pos": [c.chunk_pos.x, c.chunk_pos.y], "template_id": c.template_id, "climate": c.climate})
			copy[k] = cs
		else:
			copy[k] = v
	return copy
