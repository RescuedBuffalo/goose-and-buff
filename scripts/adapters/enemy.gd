extends Node2D
##
## A single enemy. Walks toward the core (or whichever target the wave
## director designates). Stats from data/enemies.gd.

const Enemies := preload("res://data/enemies.gd")
const Sectors := preload("res://data/sectors.gd")

@export var enemy_type: String = "GruntMelee"

signal died(self_ref: Node)
signal reached_core(self_ref: Node)

var data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var _attack_cooldown: float = 0.0
var _engaged_unit: Node2D = null

func configure(type: String) -> void:
	enemy_type = type

func _ready() -> void:
	data = Enemies.ALL[enemy_type]
	hp_max = float(data.health)
	hp = hp_max
	add_to_group("enemies")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	# If a unit is in attack range, prefer it.
	if _engaged_unit == null or not is_instance_valid(_engaged_unit):
		_engaged_unit = _find_engageable_unit()
	# Drop a hero target that went down while we were already locked onto them.
	if _engaged_unit != null and _engaged_unit.get("is_downed"):
		_engaged_unit = null
	if _engaged_unit != null and is_instance_valid(_engaged_unit):
		_engage_target(_engaged_unit.position, delta, float(data.attackRange), func(): _engaged_unit.damage(float(data.damage)))
		return
	# Otherwise march on the core. Ranged archetypes must walk to coreRange
	# (melee contact) before core damage triggers — they cannot fire from afar.
	var core_pos: Vector2 = Sectors.CORE_CENTER
	var core_range := float(data.get("coreRange", data.attackRange))
	_engage_target(core_pos, delta, core_range, func(): reached_core.emit(self))

# Handle movement and attack toward a single target position.
# range overrides which distance triggers attack (unit range vs. core range).
# on_attack is called (once per interval) when within range.
func _engage_target(target_pos: Vector2, delta: float, range: float, on_attack: Callable) -> void:
	var dist := position.distance_to(target_pos)
	if dist <= range:
		if _attack_cooldown <= 0.0:
			_attack_cooldown = float(data.attackInterval)
			on_attack.call()
		# Ranged enemies keep a preferred stand-off distance; back away if
		# the target has closed inside it.
		if data.get("keep_distance", false):
			var preferred := float(data.get("preferred_range", 0.0))
			if dist < preferred:
				_retreat_from(target_pos, delta)
		return
	_advance_toward(target_pos, delta)

func _retreat_from(target_pos: Vector2, delta: float) -> void:
	var dir := (position - target_pos).normalized()
	position += dir * float(data.moveSpeed) * delta
	position.y = clamp(position.y, Sectors.SECTOR_TOP + 16, Sectors.SECTOR_BOTTOM - 16)

func damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		died.emit(self)
		queue_free()

func apply_knockback(direction: Vector2, distance: float) -> void:
	position += direction.normalized() * distance
	# Keep enemies inside the sector's vertical band.
	position.y = clamp(position.y, Sectors.SECTOR_TOP + 16, Sectors.SECTOR_BOTTOM - 16)

func _advance_toward(target: Vector2, delta: float) -> void:
	var dir := (target - position)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	position += dir * float(data.moveSpeed) * delta

func _find_engageable_unit() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		var d := position.distance_to(u.position)
		if d < best_d and d <= float(data.attackRange) + 4.0:
			best_d = d
			best = u
	# Also consider the hero as a valid melee target when in range.
	for n in get_tree().get_nodes_in_group("hero"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if h.get("is_downed"):
			continue
		var d := position.distance_to(h.position)
		if d < best_d and d <= float(data.attackRange) + 4.0:
			best_d = d
			best = h
	return best

func _draw() -> void:
	var size: Vector2 = data.size
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, data.color_rgba, true)
	draw_rect(rect, DesignTokens.NIGHT_0, false, 2.0)
	# HP pip above the enemy.
	var hp_ratio: float = 0.0 if hp_max == 0 else hp / hp_max
	var bar_y := -size.y * 0.5 - 6.0
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x, 3.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x * hp_ratio, 3.0), DesignTokens.hp_color(hp_ratio), true)
