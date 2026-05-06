extends Node2D
##
## Projectile adapter (BUF-149). A simple traveling Node2D spawned by the
## combat adapter when a ranged weapon (bow) is fired. Travels in a
## straight line at speed_px until it either hits an enemy or exhausts
## its range.
##
## Pure logic / pure-data trivialities live in the combat resolver — this
## file is purely an animation + collision adapter on the scene tree.

signal hit_target(target_ref, amount: float)

var direction: Vector2 = Vector2.RIGHT
var speed_px: float = 720.0
var damage: float = 10.0
var range_remaining: float = 0.0
var _spent: bool = false

func configure(dir: Vector2, range_px: float, dmg: float, speed: float) -> void:
	direction = dir.normalized()
	speed_px = speed
	damage = dmg
	range_remaining = range_px
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if _spent:
		return
	var step: float = speed_px * delta
	# Travel and check for an enemy collision en route. Sweep in 3 mini
	# steps so a fast arrow can't tunnel past an enemy in one frame.
	var sub_steps: int = 3
	for i in sub_steps:
		var sub: float = step / sub_steps
		position += direction * sub
		range_remaining -= sub
		var hit: Node2D = _find_hit()
		if hit != null:
			hit_target.emit(hit, damage)
			_spent = true
			queue_free()
			return
		if range_remaining <= 0.0:
			_spent = true
			queue_free()
			return

func _find_hit() -> Node2D:
	# Cheap proximity test against the enemies group. The arrow doesn't
	# need exact collision — anything within 14 px counts as a hit so
	# the bow feels generous (placeholder feel; tighten in polish).
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if (e.position - position).length() <= 14.0:
			return e
	return null

func _draw() -> void:
	# Long thin diamond pointing along facing direction. The body is
	# rotation-baked because we set `rotation` in configure().
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color(0.92, 0.84, 0.6, 1.0), 2.0)
	draw_polygon(
		PackedVector2Array([Vector2(12, 0), Vector2(6, -3), Vector2(6, 3)]),
		PackedColorArray([Color(0.96, 0.92, 0.78), Color(0.96, 0.92, 0.78), Color(0.96, 0.92, 0.78)]),
	)
