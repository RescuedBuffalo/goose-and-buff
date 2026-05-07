class_name CombatSystem extends RefCounted
##
## Pure swing resolver. Given a hero pose + a weapon + a list of enemy
## positions, returns the targets caught inside the weapon's cone arc
## OR — for ranged weapons (BUF-149) — emits a projectile request the
## adapter spawns as a node.
##
## Cooldown is tracked here so the adapter can ask "can I swing now?"
## without owning the timer; cooldown ticks via tick(dt). The adapter
## drives the visible swing animation and floating numbers separately.
##
## Effective stats (BUF-147) are applied via set_stat_modifiers — the
## stat_system's effective_stats dict carries attack_damage / attack_speed
## / attack_range. Combat reads them and scales weapon values when
## resolving.
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
signal projectile_requested(weapon_id: String, origin: Vector2, direction: Vector2, range_px: float, damage: float, speed_px: float)
signal ammo_consumed(ammo_item_id: String, count: int)

var _cooldown_remaining: float = 0.0
# Effective-stat multipliers. 1.0 = no upgrade. Set by main.gd at run
# start from stat_system.effective_stats; reset to 1.0 on reset().
var _attack_damage_mult: float = 1.0
var _attack_speed_mult: float = 1.0
var _attack_range_bonus: float = 0.0

func reset() -> void:
	_cooldown_remaining = 0.0
	_attack_damage_mult = 1.0
	_attack_speed_mult = 1.0
	_attack_range_bonus = 0.0

func set_stat_modifiers(damage_mult: float, speed_mult: float, range_bonus_tiles: float) -> void:
	# Called once at run-start. Speed > 1.0 reduces cooldown; range bonus
	# adds tiles to the weapon's nominal range.
	_attack_damage_mult = max(0.01, damage_mult)
	_attack_speed_mult = max(0.01, speed_mult)
	_attack_range_bonus = max(0.0, range_bonus_tiles)

func tick(dt: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = max(0.0, _cooldown_remaining - dt)

func can_swing() -> bool:
	return _cooldown_remaining <= 0.0

func cooldown_remaining() -> float:
	return _cooldown_remaining

func note_swing_cooldown(weapon_id: String) -> void:
	# Stamps the cooldown as if a swing just landed (BUF-151 follow-up).
	# Used by client-side swing prediction in multiplayer: the host runs
	# the authoritative resolver, but the client still needs to gate its
	# own click cadence so a non-host peer can't spam intent RPCs faster
	# than their weapon allows. Mirrors the math in resolve_swing — both
	# paths divide weapon.cooldown by the attack-speed multiplier so
	# upgrades like buffalo_braced_shoulders apply identically on host
	# and client.
	var weapon: Dictionary = Weapons.get_weapon(weapon_id)
	_cooldown_remaining = float(weapon.cooldown) / _attack_speed_mult

func resolve_swing(origin: Vector2, facing: Vector2, weapon_id: String, enemies: Array, ammo_count: int = 0) -> Dictionary:
	# Returns {ok: bool, hits: Array[{target, damage}], reason?: String,
	# ranged: bool}. The adapter applies damage by reading the hits list
	# (melee) OR spawns a projectile from the projectile_requested signal
	# (ranged).
	if not can_swing():
		return {"ok": false, "hits": [], "reason": "cooldown"}
	var weapon: Dictionary = Weapons.get_weapon(weapon_id)
	var dir: Vector2 = facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var damage: float = float(weapon.damage) * _attack_damage_mult
	var range_tiles: float = float(weapon.range_tiles) + _attack_range_bonus
	var length_px: float = range_tiles * TILE_STEP_PX
	var half_angle_rad: float = deg_to_rad(float(weapon.arc_degrees) * 0.5)
	# Ranged path: requires ammo, emits a projectile, no immediate hits.
	# The adapter spawns an arrow Node2D and resolves contact on travel.
	if String(weapon.get("kind", "melee")) == Weapons.KIND_RANGED:
		var ammo_id: String = Weapons.ammo_for(weapon_id)
		if ammo_id.is_empty():
			return {"ok": false, "hits": [], "reason": "no_ammo_id"}
		if ammo_count < 1:
			return {"ok": false, "hits": [], "reason": "out_of_ammo", "ammo_id": ammo_id}
		_cooldown_remaining = float(weapon.cooldown) / _attack_speed_mult
		swing_started.emit(weapon_id, origin, dir, length_px, half_angle_rad)
		ammo_consumed.emit(ammo_id, 1)
		projectile_requested.emit(
			weapon_id, origin, dir, length_px, damage,
			float(weapon.get("projectile_speed_px", 720.0)),
		)
		return {"ok": true, "hits": [], "weapon": weapon_id, "ranged": true, "ammo_id": ammo_id}
	# Melee path: cone test against the enemy list, apply on hit.
	var cos_threshold: float = cos(half_angle_rad)
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
	_cooldown_remaining = float(weapon.cooldown) / _attack_speed_mult
	swing_started.emit(weapon_id, origin, dir, length_px, half_angle_rad)
	for h in hits:
		damage_dealt.emit(h.target, h.damage)
	return {"ok": true, "hits": hits, "weapon": weapon_id, "ranged": false}
