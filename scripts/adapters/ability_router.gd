extends Node
##
## Signature + help ability router (BUF-150-ish + BUF-154). Split out
## of main.gd in BUF-164.
##
## Owns:
##   try_fire_signature_ability()       — Q-bound. Local-side cooldown
##                                          stamp + RPC to host (or
##                                          local apply in solo / host).
##   host_resolve_signature(...)        — host-only resolution path
##   host_resolve_help_ability(...)     — host-only resolution path
##
## Read-only access to the local hero is via a Callable provider so
## hero respawns / puppet rebinds don't require re-attach.
##
## Effect application uses replication.host_apply_enemy_damage when the
## host is around so clients see the same hp drops; in solo it falls
## back to a direct enemy.damage() call.

const Heroes := preload("res://data/heroes.gd")
const AbilityResolverClass := preload("res://scripts/logic/ability_resolver.gd")

var sector: Node = null
var replication: Node = null
var telemetry: Telemetry = null
var _local_hero_provider: Callable = Callable()
# Resolves the local effective_stats dict so signature ability cooldown
# reads the upgrade-modified value, not the base from heroes.gd. Held
# as a Callable so respawns / run-resets don't pin a stale ref.
var _effective_stats_provider: Callable = Callable()

func attach(local_hero_provider: Callable, sector_node: Node, replication_node: Node, telemetry_node: Telemetry, effective_stats_provider: Callable = Callable()) -> void:
	_local_hero_provider = local_hero_provider
	sector = sector_node
	replication = replication_node
	telemetry = telemetry_node
	_effective_stats_provider = effective_stats_provider

# ── Signature abilities (Q) ────────────────────────────────────────────

func try_fire_signature_ability() -> void:
	var hero: Node2D = _resolve_local_hero()
	if hero == null or bool(hero.get("is_downed")):
		return
	if GameState.signature_cooldown > 0.0:
		return
	var hero_id: String = String(hero.get_meta("hero_id", GameState.hero_id))
	var data: Dictionary = Heroes.ALL.get(hero_id, Heroes.Buffalo)
	var ability_id: String = String(data.get("signatureAbilityId", "BuffaloCharge"))
	var caster_pos: Vector2 = hero.position
	var target_pos: Vector2 = hero.get_global_mouse_position()
	# Stamp cooldown locally so the HUD rail starts ticking immediately.
	# Host validates again and broadcasts the effect.
	#
	# PR #41 review: read the upgrade-modified ability_cooldown from
	# effective_stats, not data.signatureCooldown. The base value
	# ignores Buffalo charge practice / Goose loud call / Fox cutpurse
	# (-15..-20% pct on ability_cooldown), so before this fix the rail
	# snapped back to the unupgraded ceiling on every cast. Falls back
	# to the base when effective_stats hasn't been populated (direct
	# main.tscn launch path) so the ability still works there.
	var stats: Dictionary = _resolve_effective_stats()
	var cd_max: float = float(stats.get(
		"ability_cooldown",
		float(data.get("signatureCooldown", 6.0)),
	))
	GameState.set_signature_cooldown(cd_max, cd_max)
	if MpIo.is_multiplayer() and not MpIo.is_host():
		# Client → host: route through replication. Host applies and
		# broadcasts a cast event so all peers see the visual.
		replication.rpc_id(1, "_rpc_request_signature", ability_id, caster_pos, target_pos)
		return
	# Host / solo: apply locally.
	apply_signature_effects(MpIo.local_peer_id if MpIo.is_multiplayer() else 1, ability_id, caster_pos, target_pos)
	if MpIo.is_multiplayer():
		replication.rpc("_rpc_signature_visual", MpIo.local_peer_id, ability_id, caster_pos, target_pos)

func host_resolve_signature(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	if not MpIo.is_host():
		return
	apply_signature_effects(caster_peer, ability_id, caster_pos, target_pos)
	replication.rpc("_rpc_signature_visual", caster_peer, ability_id, caster_pos, target_pos)

func apply_signature_effects(caster_peer: int, ability_id: String, caster_pos: Vector2, target_pos: Vector2) -> void:
	var effects: Array = AbilityResolverClass.resolve(ability_id, caster_pos, target_pos)
	for effect in effects:
		_apply_signature_effect(effect, caster_peer)
	if telemetry != null:
		telemetry.log("ability_cast", {
			"ability_id": ability_id,
			"caster_peer": caster_peer,
		})

# ── Help abilities (E) ─────────────────────────────────────────────────

func host_resolve_help_ability(caster_peer: int, target_peer: int) -> void:
	if not MpIo.is_host():
		return
	var caster: Node2D = replication.hero_for_peer(caster_peer)
	var target: Node2D = replication.hero_for_peer(target_peer)
	if caster == null or target == null:
		return
	var caster_hero_id: String = String(caster.get_meta("hero_id", ""))
	var ability_id: String = ""
	match caster_hero_id:
		"Buffalo": ability_id = "BuffaloStampede"
		"Goose": ability_id = "GooseCover"
		"Fox": ability_id = "FoxSteal"
		_: return
	# Resolve via AbilityResolver — pure logic produces the effect dicts;
	# the host applies them and broadcasts the cast event so every peer
	# can play the visual.
	var effects: Array = AbilityResolverClass.resolve_help(ability_id, caster.position, target.position, _gather_enemy_refs())
	for effect in effects:
		_apply_help_effect(effect, caster, target)
	# Broadcast the cast so all peers see the visual flash.
	replication.rpc("_rpc_help_ability", caster_peer, target_peer, ability_id)
	if telemetry != null:
		telemetry.log("help_ability_cast", {
			"caster_peer": caster_peer,
			"target_peer": target_peer,
			"ability_id": ability_id,
		})

# ── Effect application ─────────────────────────────────────────────────

func _apply_signature_effect(effect: Dictionary, caster_peer: int) -> void:
	var kind: String = String(effect.get("kind", ""))
	var enemies: Array = _gather_enemy_refs()
	match kind:
		"damage_in_capsule":
			var from: Vector2 = effect.from
			var to: Vector2 = effect.to
			var width: float = float(effect.width)
			var dmg: float = float(effect.damage)
			for e in enemies:
				if _point_to_segment_distance(e.position, from, to) <= width:
					if MpIo.is_host():
						replication.host_apply_enemy_damage(e, dmg)
					else:
						e.damage(dmg)
			# Caster slides along the capsule path (Buffalo charge feel).
			var caster: Node2D = replication.hero_for_peer(caster_peer)
			if caster != null and is_instance_valid(caster):
				caster.position = to
				if sector != null:
					caster.current_tile = sector.world_to_tile(to)
		"damage_in_cone":
			var from: Vector2 = effect.from
			var dir: Vector2 = effect.direction
			var length: float = float(effect.length)
			var half_angle: float = float(effect.half_angle)
			var dmg: float = float(effect.damage)
			var cos_threshold: float = cos(half_angle)
			for e in enemies:
				var to_e: Vector2 = e.position - from
				var dist: float = to_e.length()
				if dist > length or dist < 0.0001:
					continue
				if to_e.normalized().dot(dir) < cos_threshold:
					continue
				if MpIo.is_host():
					replication.host_apply_enemy_damage(e, dmg)
				else:
					e.damage(dmg)
		"dash_and_strike":
			var to: Vector2 = effect.to
			var radius: float = float(effect.radius)
			var dmg: float = float(effect.damage)
			var caster: Node2D = replication.hero_for_peer(caster_peer)
			if caster != null and is_instance_valid(caster):
				caster.position = to
				if sector != null:
					caster.current_tile = sector.world_to_tile(to)
			for e in enemies:
				if (e.position - to).length() <= radius:
					if MpIo.is_host():
						replication.host_apply_enemy_damage(e, dmg)
					else:
						e.damage(dmg)
		_:
			pass

func _apply_help_effect(effect: Dictionary, caster: Node2D, _target: Node2D) -> void:
	# Effect shapes:
	#   { "kind": "line_charge", "from": Vector2, "to": Vector2,
	#     "width": float, "damage": float, "shield_seconds": float }
	#   { "kind": "buff_zone", "center_pos": Vector2, "radius": float,
	#     "duration": float, "attack_speed_mult": float, "damage_resist": float }
	#   { "kind": "mark_target", "target_enemy": ref, "damage_mult": float, "yank_to_pos": Vector2 }
	var kind: String = String(effect.get("kind", ""))
	match kind:
		"line_charge":
			# Damage every enemy within `width` of the line from→to.
			var from: Vector2 = effect.from
			var to: Vector2 = effect.to
			var width: float = float(effect.width)
			var dmg: float = float(effect.damage)
			for n in _gather_enemy_refs():
				if _point_to_segment_distance(n.position, from, to) <= width:
					replication.host_apply_enemy_damage(n, dmg)
			# Teleport the caster to the line endpoint so Stampede reads
			# as a charge across the world rather than a stationary AoE.
			caster.position = to
			if sector != null:
				caster.current_tile = sector.world_to_tile(to)
		"buff_zone":
			# v1 implementation: telemetry + visual flash only. The
			# mechanical buff is tracked under BUF-171.
			pass
		"mark_target":
			# v1 implementation: damage the marked enemy directly.
			var enemy_ref = effect.get("target_enemy")
			if enemy_ref != null and is_instance_valid(enemy_ref):
				replication.host_apply_enemy_damage(enemy_ref, float(effect.get("damage", 0.0)) * float(effect.get("damage_mult", 2.0)))
		_:
			pass

# ── helpers ──────────────────────────────────────────────────────────

func _resolve_local_hero() -> Node2D:
	if _local_hero_provider.is_null():
		return null
	var ref = _local_hero_provider.call()
	if ref == null or not is_instance_valid(ref):
		return null
	return ref as Node2D

func _resolve_effective_stats() -> Dictionary:
	if _effective_stats_provider.is_null():
		return {}
	var ref = _effective_stats_provider.call()
	if typeof(ref) != TYPE_DICTIONARY:
		return {}
	return ref

func _gather_enemy_refs() -> Array:
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			enemies.append(n)
	return enemies

func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clamp((p - a).dot(ab) / max(ab.length_squared(), 0.001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)
