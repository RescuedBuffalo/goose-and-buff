class_name GatherSystem extends RefCounted
##
## Pure gather state. The hero holds E within 1 tile of a resource node;
## gather progress depletes the node's HP per-second based on the
## equipped tool's affinity for the node's primary yield (a hand axe
## pulls wood at 3x base, etc.). When HP hits 0, the system emits
## gather_completed with a rolled yield — the adapter pushes that into
## the inventory.
##
## Single-hero MVP — only one active gather at a time. The active node
## reference is held externally (a Node2D in the scene); the system
## tracks progress numerically and asks the system not to read scene
## state. The adapter is responsible for keeping the node's hp_visual
## in sync via the gather_progress signal.

const Resources := preload("res://data/resources.gd")
const Weapons := preload("res://data/weapons.gd")

# How much HP a swing of gathering removes per second at base rate
# (bare hands, no affinity). Tool affinity multiplies this.
const BASE_GATHER_RATE := 6.0

# Maximum tile distance from the hero to the gather target. If the hero
# walks too far, the active gather is cancelled silently.
const MAX_GATHER_DISTANCE_TILES := 1

signal gather_started(node_ref)
signal gather_progress(node_ref, hp_remaining: float, hp_max: float)
signal gather_completed(node_ref, yields: Dictionary)
signal gather_cancelled(node_ref)

var _active_node: Object = null
var _active_kind: String = ""
var _active_hp: float = 0.0
var _active_hp_max: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Effective-stat multiplier for gather speed (BUF-147). 1.0 = base.
var _speed_mult: float = 1.0

func reset() -> void:
	cancel_active()
	_rng.randomize()
	_speed_mult = 1.0

func set_speed_multiplier(mult: float) -> void:
	_speed_mult = max(0.01, mult)

func is_active() -> bool:
	return _active_node != null and is_instance_valid(_active_node)

func active_node() -> Object:
	return _active_node

func start_gather(node_ref: Object, resource_kind: String, hp: float, hp_max: float) -> void:
	if _active_node != null and _active_node != node_ref:
		cancel_active()
	_active_node = node_ref
	_active_kind = resource_kind
	_active_hp = hp
	_active_hp_max = hp_max
	gather_started.emit(node_ref)
	gather_progress.emit(node_ref, _active_hp, _active_hp_max)

func cancel_active() -> void:
	if _active_node == null:
		return
	var n := _active_node
	_active_node = null
	_active_kind = ""
	_active_hp = 0.0
	_active_hp_max = 0.0
	if is_instance_valid(n):
		gather_cancelled.emit(n)

func tick(dt: float, hero_tile: Vector2i, node_tile: Vector2i, equipped_weapon_id: String) -> void:
	if not is_active():
		return
	var dist: int = abs(hero_tile.x - node_tile.x) + abs(hero_tile.y - node_tile.y)
	if dist > MAX_GATHER_DISTANCE_TILES:
		cancel_active()
		return
	var multiplier: float = _affinity_for_kind(_active_kind, equipped_weapon_id)
	var rate: float = BASE_GATHER_RATE * multiplier * _speed_mult
	_active_hp = max(0.0, _active_hp - rate * dt)
	gather_progress.emit(_active_node, _active_hp, _active_hp_max)
	if _active_hp <= 0.0:
		var yields: Dictionary = Resources.roll_yield(_active_kind, _rng)
		var n := _active_node
		_active_node = null
		_active_kind = ""
		_active_hp = 0.0
		_active_hp_max = 0.0
		gather_completed.emit(n, yields)

# ── internals ─────────────────────────────────────────────────────────

func _affinity_for_kind(resource_kind: String, weapon_id: String) -> float:
	# Pick the best multiplier across all items in the resource's yield
	# table. If the resource yields wood and we hold a hand axe, the
	# hand axe's wood multiplier (3.0) wins. Bare hands always 1.0.
	var data: Dictionary = Resources.get_resource(resource_kind)
	var yields: Dictionary = data.get("yields", {})
	var best: float = 1.0
	for item_id in yields:
		var m: float = Weapons.gather_multiplier(weapon_id, item_id)
		if m > best:
			best = m
	return best
