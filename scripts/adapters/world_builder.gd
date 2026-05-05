extends Node
##
## World builder adapter (BUF-144). Consumes a WorldDef from the world
## generator and spawns resource-node Node2Ds at the tiles the def
## describes. Owns nothing except the spawned children, which get
## reparented under `world_root` so a clean teardown/rebuild path
## exists (run-end → run-start clears them via clear()).
##
## This is intentionally a Node, not a Node2D — the resource nodes
## position themselves; the builder is just a controller.

const Sectors := preload("res://data/sectors.gd")
const ResourceNodeScene := preload("res://scenes/resource_node.tscn")

var sector: Node = null
var world_root: Node = null
var _spawned: Array = []  # weak Node2D refs to children we spawned

func attach(sector_ref: Node, root: Node) -> void:
	sector = sector_ref
	world_root = root

func build_from(def: Dictionary) -> void:
	if sector == null or world_root == null:
		push_warning("WorldBuilder: attach() before build_from()")
		return
	clear()
	var resources: Array = def.get("resources", [])
	for entry in resources:
		var tile: Vector2i = entry.tile
		if not Sectors.is_tile_in_grid(tile):
			continue
		if Sectors.is_tile_protected(tile):
			# Belt-and-braces: the generator already strips resources
			# inside the protected radius, but if a future template
			# placement leaks one in, refuse it here.
			continue
		if not sector.is_tile_walkable(tile):
			# Water or already-blocked tile (e.g. a chunk overlap).
			# Skip rather than crash.
			continue
		var n: Node2D = ResourceNodeScene.instantiate()
		n.configure(String(entry.kind))
		n.attach_sector(sector)
		world_root.add_child(n)
		n.place_at_tile(tile)
		_spawned.append(n)

func clear() -> void:
	for n in _spawned:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
