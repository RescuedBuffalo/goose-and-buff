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
const WorldGeneratorTest := preload("res://scripts/tests/world_generator_test.gd")
const AbilityResolverTest := preload("res://scripts/tests/ability_resolver_test.gd")

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
		# Template id + biome tag label at the chunk's center tile. The
		# biome tag (BUF-146) reads as the placeholder variant under the
		# climate tier — useful when the same climate has multiple shapes.
		var center_tile := origin_tile + Vector2i(Chunks.CHUNK_SIZE / 2, Chunks.CHUNK_SIZE / 2)
		var center_world: Vector2 = sector.tile_to_world(center_tile)
		var font: Font = ThemeDB.fallback_font
		var biome: String = String(entry.get("biome", entry.climate))
		var template_label: String = String(entry.template_id)
		var biome_label: String = "[%s]" % biome
		draw_string(font, center_world + Vector2(-40, -4), template_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		draw_string(font, center_world + Vector2(-40, 12), biome_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
	# AStar connectivity hotspots — flag walkable tiles with 0/1/2 walkable
	# 4-neighbours. Zero/one means a dead-end pocket (the path planner can
	# reach but can't escape without backtracking through the same tile).
	# Two means a one-tile corridor pinch — fine in practice but useful to
	# eyeball when a chunk template feels claustrophobic.
	_draw_astar_hotspots()

func _color_for_climate(climate: String) -> Color:
	match climate:
		"temperate": return Color(1.0, 0.85, 0.55, 0.85)
		"frosted":   return Color(0.7, 0.85, 1.0, 0.85)
		"frozen":    return Color(0.7, 0.95, 1.0, 0.95)
		_:           return Color(1.0, 1.0, 1.0, 0.6)

func _draw_astar_hotspots() -> void:
	# Read AStar straight off the sector — the sector is a Node so we have
	# to gate every property access. is_tile_walkable() already checks
	# AStar so we re-use it for connectivity counting and stay consistent
	# with whatever the path planner actually sees.
	if sector == null or not sector.has_method("is_tile_walkable"):
		return
	var grid_size: Vector2i = Sectors.TILE_GRID_SIZE
	var dirs: Array = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for ty in grid_size.y:
		for tx in grid_size.x:
			var tile := Vector2i(tx, ty)
			if not sector.is_tile_walkable(tile):
				continue
			var n: int = 0
			for d in dirs:
				if sector.is_tile_walkable(tile + d):
					n += 1
			if n >= 3:
				continue
			# 0 / 1 walkable neighbours = dead-end pocket (red).
			# 2 walkable neighbours = one-tile corridor pinch (yellow).
			var color: Color = Color(0.92, 0.36, 0.36, 0.8) if n <= 1 else Color(0.95, 0.78, 0.36, 0.7)
			var center: Vector2 = sector.tile_to_world(tile)
			draw_circle(center, 6.0, color)
			draw_arc(center, 6.0, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.6), 1.0)

# ── F4: WorldDef dump for offline inspection ─────────────────────────

func dump_world(run_seed: int) -> void:
	# Filename pattern matches the BUF-145 ticket: world_<timestamp>.json,
	# with the seed string embedded inside the file's metadata block so a
	# dev can grep the dump dir for a specific timestamp first, seed
	# second.
	if world_def.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DEBUG_DUMP_DIR)
	var ts: int = int(Time.get_unix_time_from_system())
	var path: String = "%s/world_%d.json" % [DEBUG_DUMP_DIR, ts]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("debug: could not open %s" % path)
		return
	# Vector2i / Vector2 don't json natively — flatten into [x, y] pairs.
	var payload: Dictionary = _flatten_for_json(world_def)
	payload["dumped_at"] = ts
	payload["seed_string"] = WorldGeneratorClass.seed_to_string(run_seed)
	f.store_string(JSON.stringify(payload, "\t"))
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
			var stat_report: Dictionary = StatSystemTest.run_all()
			StatSystemTest.print_results(stat_report)
			var world_report: Dictionary = WorldGeneratorTest.run_all()
			WorldGeneratorTest.print_results(world_report)
			var ability_report: Dictionary = AbilityResolverTest.run_all()
			AbilityResolverTest.print_results(ability_report)
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
				cs.append({
					"chunk_pos": [c.chunk_pos.x, c.chunk_pos.y],
					"template_id": c.template_id,
					"climate": c.climate,
					"biome": String(c.get("biome", c.climate)),
				})
			copy[k] = cs
		else:
			copy[k] = v
	return copy
