class_name CombatSystem extends RefCounted
##
## Pure swing resolver. Given a hero pose + a weapon + a list of enemy
## positions, returns the targets caught inside the weapon's cone arc.
##
## Cooldown is tracked here so the adapter can ask "can I swing now?"
## without owning the timer; cooldown ticks via tick(dt). The adapter
## drives the visible swing animation and floating numbers separately.
##
## Hero damage from enemies is NOT modeled here — enemy adapters call
## hero.damage() directly on adjacency, same contract as the Phase 1
## build. CombatSystem is the *outgoing* hero swing, full stop.

const Weapons := preload("res://data/weapons.gd")

# Pixel distance between adjacent isometric tile centers — used to convert
# weapon range_tiles into a pixel range for the cone test. Mirrors the
# constant in hero/enemy adapters.
const TILE_STEP_PX := 35.0

signal swing_started(weapon_id: String, origin: Vector2, direction: Vector2, length_px: float, half_angle_rad: float)
signal damage_dealt(target_ref, amount: float)

var _cooldown_remaining: float = 0.0

func reset() -> void:
	_cooldown_remaining = 0.0

func tick(dt: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = max(0.0, _cooldown_remaining - dt)

func can_swing() -> bool:
	return _cooldown_remaining <= 0.0

func cooldown_remaining() -> float:
	return _cooldown_remaining

func resolve_swing(origin: Vector2, facing: Vector2, weapon_id: String, enemies: Array) -> Dictionary:
	# Returns {ok: bool, hits: Array[{target, damage}], reason?: String}.
	# The adapter applies damage by reading the hits list.
	if not can_swing():
		return {"ok": false, "hits": [], "reason": "cooldown"}
	var weapon: Dictionary = Weapons.get_weapon(weapon_id)
	var dir: Vector2 = facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var length_px: float = float(weapon.range_tiles) * TILE_STEP_PX
	var half_angle_rad: float = deg_to_rad(float(weapon.arc_degrees) * 0.5)
	var cos_threshold: float = cos(half_angle_rad)
	var damage: float = float(weapon.damage)
	var hits: Array = []
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.position - origin
		var dist: float = to_enemy.length()
		if dist <= 0.0001 or dist > length_px:
			continue
		if to_enemy.normalized().dot(dir) < cos_threshold:
			continue
		hits.append({"target": enemy, "damage": damage})
	_cooldown_remaining = float(weapon.cooldown)
	swing_started.emit(weapon_id, origin, dir, length_px, half_angle_rad)
	for h in hits:
		damage_dealt.emit(h.target, h.damage)
	return {"ok": true, "hits": hits, "weapon": weapon_id}
