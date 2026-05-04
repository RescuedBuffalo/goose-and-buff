extends Node2D
##
## A deployed unit. Holds formation behind the leader (Buffalo) and only
## breaks off to engage when an enemy enters its detection bubble.
## Stats come from data/units.gd.

# UnitsData is reachable via class_name from data/units.gd — no preload alias.
const Sectors := preload("res://data/sectors.gd")

const PIXELS_PER_STUD := 12.0
# Detection radius around the unit. Enemies inside this are engaged;
# otherwise the unit holds formation behind the leader. Ranged units get a
# bigger bubble (their attack range exceeds the baseline).
const BASE_DETECTION_RADIUS := 220.0
# Distance under which a unit considers itself "in formation" and stops
# moving — prevents jitter when the leader is stationary.
const FORMATION_SLOP := 6.0
# Beyond this distance from the leader, the unit auto-drops any enemy
# target and chases. So just running away gathers the army back up,
# without the player ever having to press the retreat key.
const LEASH_DISTANCE := 320.0

@export var unit_id: String = "Calf"

var unit_data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var move_pixels_per_second: float = 0.0
var attack_range_px: float = 0.0
var attack_interval: float = 0.0
var damage_amount: float = 0.0
var detection_range_px: float = 0.0
var _attack_cooldown: float = 0.0

var leader: Node2D = null
var formation_offset: Vector2 = Vector2.ZERO
var _scripted_motion: bool = false  # disables AI while a tween moves us

func configure(id: String) -> void:
	unit_id = id

func bind_leader(node: Node2D, offset: Vector2) -> void:
	leader = node
	formation_offset = offset

func set_scripted_motion(active: bool) -> void:
	# Called by main.gd while it tweens the unit back to the base on wave
	# end. AI stays off until the tween releases us.
	_scripted_motion = active

func _ready() -> void:
	unit_data = UnitsData.ALL[unit_id]
	hp_max = float(unit_data.health)
	hp = hp_max
	move_pixels_per_second = float(unit_data.moveSpeed) * PIXELS_PER_STUD
	attack_range_px = float(unit_data.attackRange) * PIXELS_PER_STUD
	attack_interval = float(unit_data.attackInterval)
	damage_amount = float(unit_data.damage)
	# A unit's detection bubble must at least cover its attack range, plus
	# a buffer so it sees enemies before they're already on top of it.
	detection_range_px = max(BASE_DETECTION_RADIUS, attack_range_px + 80.0)
	add_to_group("units")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if hp <= 0.0 or _scripted_motion:
		return
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	# Two reasons to skip the engage branch and only follow:
	# 1. Player toggled retreat — explicit M-click semantics.
	# 2. Leader has run far enough that the leash snaps — auto-disengage.
	var leader_far := false
	if leader != null and is_instance_valid(leader):
		leader_far = position.distance_to(leader.position) > LEASH_DISTANCE
	var following_only: bool = GameState.retreat_mode or leader_far
	if not following_only:
		var target := _find_enemy_in_detection()
		if target != null:
			var dist := position.distance_to(target.position)
			if dist > attack_range_px:
				_advance_toward(target.position, delta)
			elif _attack_cooldown <= 0.0:
				_attack_cooldown = attack_interval
				target.damage(damage_amount)
			return
	# No engage — fall in behind the leader.
	if leader != null and is_instance_valid(leader):
		var anchor: Vector2 = leader.position + formation_offset
		if position.distance_to(anchor) > FORMATION_SLOP:
			_advance_toward(anchor, delta)

func damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		queue_free()

func _advance_toward(target: Vector2, delta: float) -> void:
	var dir := (target - position)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	position += dir * move_pixels_per_second * delta

func _find_enemy_in_detection() -> Node2D:
	# Nearest enemy within the unit's detection bubble. Outside that, the
	# unit ignores them and stays with the leader.
	var best: Node2D = null
	var best_d := detection_range_px
	for n in get_tree().get_nodes_in_group("enemies"):
		var enemy := n as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var d := position.distance_to(enemy.position)
		if d < best_d:
			best_d = d
			best = enemy
	return best

func _draw() -> void:
	var color := _color_for_archetype()
	var size := _size_for_archetype()
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, color, true)
	# Outline in the faction ink color.
	draw_rect(rect, DesignTokens.ink_color(unit_data.faction), false, 2.0)
	# HP bar above the unit.
	var hp_ratio: float = 0.0 if hp_max == 0 else hp / hp_max
	var bar_w := size.x
	var bar_y := -size.y * 0.5 - 6.0
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, 3.0), DesignTokens.hp_color(hp_ratio), true)

func _color_for_archetype() -> Color:
	# Buffalo palette tints by archetype so the three units read distinctly.
	match unit_data.archetype:
		"light": return DesignTokens.PARCHMENT_1
		"ranged": return DesignTokens.PARCHMENT_2
		"heavy": return DesignTokens.BUFFALO_CORE
		_: return DesignTokens.PARCHMENT_0

func _size_for_archetype() -> Vector2:
	match unit_data.archetype:
		"light": return Vector2(22, 22)
		"ranged": return Vector2(22, 26)
		"heavy": return Vector2(30, 30)
		_: return Vector2(22, 22)
