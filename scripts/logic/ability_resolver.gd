class_name AbilityResolver extends RefCounted
##
## Pure ability resolution. Given an ability id, the caster's position,
## and a targeting payload, return a list of effects. Adapters apply the
## effects to the scene tree. Mirror of Roblox AbilityResolver.resolve().
##
## Effect shapes:
##   { "kind": "damage_in_capsule", "from": Vector2, "to": Vector2,
##     "width": float, "damage": float, "knockback": float,
##     "direction": Vector2 }
##   { "kind": "damage_in_cone", "from": Vector2, "direction": Vector2,
##     "length": float, "half_angle": float (radians),
##     "damage": float, "knockback": float }
##   { "kind": "dash_and_strike", "from": Vector2, "to": Vector2,
##     "radius": float, "damage": float, "backstab_multiplier": float,
##     "direction": Vector2 }

const Cards := preload("res://data/cards.gd")

# Help-ability tunables (BUF-154). v1 numbers; tune after first
# 3-player playtest. Each ability operates on world-space positions
# the caller supplies and may peek at the live enemy list (passed in)
# for mark/yank effects.
const HELP_STAMPEDE_WIDTH := 48.0
const HELP_STAMPEDE_DAMAGE := 35.0
const HELP_STAMPEDE_SHIELD := 3.0
const HELP_COVER_RADIUS := 80.0
const HELP_COVER_DURATION := 6.0
const HELP_COVER_ATTACK_SPEED := 1.5
const HELP_COVER_DAMAGE_RESIST := 0.4
const HELP_STEAL_RADIUS := 64.0
const HELP_STEAL_DAMAGE := 18.0
const HELP_STEAL_DAMAGE_MULT := 2.0

static func resolve(ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> Array:
	match ability_id:
		"BuffaloCharge":
			return _resolve_buffalo_charge(caster_pos, target_pos)
		"Dive":
			return _resolve_dive(caster_pos, target_pos)
		"Snatch":
			return _resolve_snatch(caster_pos, target_pos)
		_:
			return []

static func resolve_help(ability_id: String, caster_pos: Vector2, target_pos: Vector2, enemies: Array) -> Array:
	# Help abilities (BUF-154). Caster is always the hero issuing the
	# ability; target is the teammate they're helping. Enemies list is
	# host-authoritative — used for the "find an enemy near the target"
	# logic on Steal.
	match ability_id:
		"BuffaloStampede":
			return [{
				"kind": "line_charge",
				"from": caster_pos,
				"to": target_pos,
				"width": HELP_STAMPEDE_WIDTH,
				"damage": HELP_STAMPEDE_DAMAGE,
				"shield_seconds": HELP_STAMPEDE_SHIELD,
				"direction": (target_pos - caster_pos).normalized() if (target_pos - caster_pos).length_squared() > 0.0001 else Vector2.RIGHT,
			}]
		"GooseCover":
			return [{
				"kind": "buff_zone",
				"center_pos": target_pos,
				"radius": HELP_COVER_RADIUS,
				"duration": HELP_COVER_DURATION,
				"attack_speed_mult": HELP_COVER_ATTACK_SPEED,
				"damage_resist": HELP_COVER_DAMAGE_RESIST,
			}]
		"FoxSteal":
			# Pick the closest enemy to the target hero — that's the one
			# Fox marks. v1 returns a damage payload + the marked enemy
			# ref for the host adapter to apply.
			var best_enemy = null
			var best_d: float = INF
			for e in enemies:
				if e == null or not is_instance_valid(e):
					continue
				var d: float = (e.position - target_pos).length()
				if d <= HELP_STEAL_RADIUS and d < best_d:
					best_d = d
					best_enemy = e
			if best_enemy == null:
				return []
			return [{
				"kind": "mark_target",
				"target_enemy": best_enemy,
				"damage": HELP_STEAL_DAMAGE,
				"damage_mult": HELP_STEAL_DAMAGE_MULT,
				"yank_to_pos": caster_pos,
			}]
		_:
			return []

static func _resolve_buffalo_charge(caster_pos: Vector2, target_pos: Vector2) -> Array:
	var card: Dictionary = Cards.get_card("card.charge")
	var payload: Dictionary = card.payload
	var dir := (target_pos - caster_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end := caster_pos + dir * float(payload.length)
	return [{
		"kind": "damage_in_capsule",
		"from": caster_pos,
		"to": end,
		"width": float(payload.width),
		"damage": float(payload.damage),
		"knockback": float(payload.knockback),
		"direction": dir,
	}]

static func _resolve_dive(caster_pos: Vector2, target_pos: Vector2) -> Array:
	var card: Dictionary = Cards.get_card("card.dive")
	var payload: Dictionary = card.payload
	var dir := (target_pos - caster_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	return [{
		"kind": "damage_in_cone",
		"from": caster_pos,
		"direction": dir,
		"length": float(payload.length),
		"half_angle": deg_to_rad(float(payload.half_angle_deg)),
		"damage": float(payload.damage),
		"knockback": float(payload.knockback),
	}]

static func _resolve_snatch(caster_pos: Vector2, target_pos: Vector2) -> Array:
	# Fox dashes toward the targeted point (range-capped) and strikes any
	# enemy near the dash endpoint. The "behind" check reads the enemy's
	# facing direction from world layout — enemies enter from the right and
	# walk left, so an enemy with x > caster_end.x has been stepped past.
	var card: Dictionary = Cards.get_card("card.snatch")
	var payload: Dictionary = card.payload
	var delta := target_pos - caster_pos
	var dist := delta.length()
	var dir: Vector2
	if dist <= 0.0001:
		dir = Vector2.RIGHT
		dist = 1.0
	else:
		dir = delta / dist
	var dash_distance: float = min(dist, float(payload.max_dash))
	var dash_to: Vector2 = caster_pos + dir * dash_distance
	return [{
		"kind": "dash_and_strike",
		"from": caster_pos,
		"to": dash_to,
		"radius": float(payload.strike_radius),
		"damage": float(payload.damage),
		"backstab_multiplier": float(payload.backstab_multiplier),
		"direction": dir,
	}]
