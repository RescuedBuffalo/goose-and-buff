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

const Cards := preload("res://data/cards.gd")

static func resolve(ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> Array:
	match ability_id:
		"BuffaloCharge":
			return _resolve_buffalo_charge(caster_pos, target_pos)
		"Dive":
			return _resolve_dive(caster_pos, target_pos)
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
