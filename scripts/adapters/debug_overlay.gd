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
		var top := sector.tile_to_world(origin_tile)
		var right := sector.tile_to_world(origin_tile + Vector2i(Chunks.CHUNK_SIZE, 0))
		var bottom := sector.tile_to_world(origin_tile + Vector2i(Chunks.CHUNK_SIZE, Chunks.CHUNK_SIZE))
		var left := sector.tile_to_world(origin_tile + Vector2i(0, Chunks.CHUNK_SIZE))
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
