extends Node2D
##
## Enemy adapter — tile-locked raider. Walks toward the lodge core via
## the sector's AStarGrid2D, engages the hero on adjacency. The wave-
## defense build engaged units first; the survival rebuild prefers the
## hero (since there are no deployed units yet) but falls back to the
## lodge core if the hero is too far / downed.
##
## Hero damage was flagged "pending" in the wave-defense notes — survival
## requires it, so adjacency damage to the hero is now first-class. Walls
## block movement, which makes the path snake around them; the AI doesn't
## yet attack walls in MVP (flagged in PROTOTYPE-NOTES).

const Enemies := preload("res://data/enemies.gd")
const Sectors := preload("res://data/sectors.gd")

const TILE_STEP_PX := 35.0
const PX_PER_TILE := 32.0

@export var enemy_type: String = "FrostWolf"

signal died(self_ref: Node)
signal reached_core(self_ref: Node)
signal damaged_target(target_ref: Node, amount: float)

var data: Dictionary
var hp_max: float = 0.0
var hp: float = 0.0
var current_tile: Vector2i = Vector2i.ZERO
var sector: Node = null
var attack_range_tiles: int = 1
var core_range_tiles: int = 1
var preferred_range_tiles: int = 0

# Per-round difficulty multipliers (BUF-115). Set by main.gd at spawn
# time from waves.gd's stat_scale_for(round_index). Defaults to 1.0
# everywhere so direct callers / tests still get base stats.
var _hp_scale: float = 1.0
var _damage_scale: float = 1.0

var _attack_cooldown: float = 0.0
var _moving: bool = false
var _engaged_target: Node2D = null
# Set true between emitting reached_core and the queue_free completing
# at end of frame. damage() returns early on this so a same-frame combat
# hit can't double-credit the kill (counted once when reaching core,
# again when damage drops hp to 0).
var _consumed_by_core: bool = false

func configure(type: String, stat_scale: Dictionary = {}) -> void:
	enemy_type = type
	_hp_scale = float(stat_scale.get("hp", 1.0))
	_damage_scale = float(stat_scale.get("damage", 1.0))

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func place_at_tile(tile: Vector2i) -> void:
	current_tile = tile
	if sector != null:
		position = sector.tile_to_world(current_tile)

func _ready() -> void:
	# Take a per-instance copy so we can stamp the round-scaled HP and
	# damage onto `data` without mutating the constant table in
	# enemies.gd (every enemy of the same type would inherit it).
	data = Enemies.ALL[enemy_type].duplicate(true)
	data.health = float(data.health) * _hp_scale
	data.damage = float(data.damage) * _damage_scale
	hp_max = float(data.health)
	hp = hp_max
	attack_range_tiles = max(1, int(round(float(data.attackRange) / PX_PER_TILE)))
	core_range_tiles = max(1, int(round(float(data.get("coreRange", data.attackRange)) / PX_PER_TILE)))
	preferred_range_tiles = int(round(float(data.get("preferred_range", 0.0)) / PX_PER_TILE))
	add_to_group("enemies")
	y_sort_enabled = true
	queue_redraw()

func damage(amount: float) -> void:
	# Guard re-entry: a multi-hit frame (two arrows, melee + arrow) can
	# call damage() on a node whose hp already hit 0 but whose queue_free
	# hasn't completed yet. Without this guard, died.emit fires twice and
	# the kill counts as two — inflating embers + telemetry.
	# Also bail if this enemy already reached the core this frame —
	# damage applied after reached_core would otherwise double-credit
	# the kill (once via lodge damage, once via died.emit).
	if hp <= 0.0 or _consumed_by_core:
		return
	hp = max(0.0, hp - amount)
	queue_redraw()
	if hp <= 0.0:
		died.emit(self)
		queue_free()

func apply_knockback(direction: Vector2, distance: float) -> void:
	if sector == null:
		return
	var tiles: int = int(round(distance / PX_PER_TILE))
	if tiles <= 0:
		return
	var step: Vector2i
	if abs(direction.x) >= abs(direction.y):
		step = Vector2i(int(sign(direction.x)), 0)
	else:
		step = Vector2i(0, int(sign(direction.y)))
	var target := current_tile
	for i in tiles:
		var probe: Vector2i = target + step
		if not sector.is_tile_walkable(probe):
			break
		target = probe
	if target != current_tile:
		current_tile = target
		position = sector.tile_to_world(current_tile)

func _physics_process(delta: float) -> void:
	if hp <= 0.0 or sector == null:
		return
	# Freeze enemy AI once the run ends so wolves don't keep pathing
	# / attacking behind the end-screen scrim. Mirrors main.gd's
	# tick guard. Enemies are queue_freed on restart.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	# Multiplayer puppets don't run AI — the host owns enemy decisions
	# and broadcasts position snapshots. Clients update position from
	# replication RPCs and skip the local pathfinding tick. The meta
	# flag is set by the replication adapter when it spawns enemies.
	if has_meta("is_puppet") and bool(get_meta("is_puppet")):
		return
	# Tick cooldown even while mid-step so a moving wolf's effective
	# attack cadence matches a stationary one. Without this, attack
	# cooldown stalls during ~0.4s per-tile tweens, which silently
	# stretched the effective interval well past `data.attackInterval`.
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	if _moving:
		# Movement decision still gated — don't replan mid-step. Cooldown
		# already ticked above.
		return
	# Refresh hero engagement once per tile rather than every frame.
	if _engaged_target == null or not is_instance_valid(_engaged_target):
		_engaged_target = _find_engageable_target()
	if _engaged_target != null and _engaged_target.get("is_downed"):
		_engaged_target = null
	if _engaged_target != null and is_instance_valid(_engaged_target):
		var t_tile: Vector2i = _engaged_target.current_tile
		var dist: int = sector.tile_distance(current_tile, t_tile)
		if dist <= attack_range_tiles:
			if _attack_cooldown <= 0.0:
				_attack_cooldown = float(data.attackInterval)
				# Emit *applied* damage rather than attempted: target.damage()
				# clamps HP at zero, so a 20-dmg hit on a 5-HP hero only
				# applies 5. Snapshot pre-damage HP to compute the delta.
				#
				# Object.get(property) is single-arg in Godot 4 — null if
				# the property doesn't exist; we coerce to 0.0 ourselves
				# rather than passing a default arg.
				var pre_val = _engaged_target.get("hp")
				var pre_hp: float = float(pre_val) if pre_val != null else 0.0
				_engaged_target.damage(float(data.damage))
				var post_val = _engaged_target.get("hp")
				var post_hp: float = float(post_val) if post_val != null else 0.0
				var applied: float = max(0.0, pre_hp - post_hp)
				damaged_target.emit(_engaged_target, applied)
			if data.get("keep_distance", false) and dist < preferred_range_tiles:
				_step_away_from(t_tile)
			return
		_step_toward(t_tile)
		return
	# Default goal: lodge core. Reaching adjacency damages the lodge.
	var dist_to_core: int = sector.tile_distance(current_tile, Sectors.LODGE_TILE)
	if dist_to_core <= core_range_tiles:
		if _attack_cooldown <= 0.0:
			_attack_cooldown = float(data.attackInterval)
			# Mark as consumed BEFORE emit so any same-frame damage from
			# the player (a melee swing landing on this tile, an arrow
			# in flight) is rejected by damage(). Without this, the kill
			# counts twice: once for lodge damage, once for the post-emit
			# hit dropping hp to 0.
			_consumed_by_core = true
			reached_core.emit(self)
		return
	_step_toward(Sectors.LODGE_TILE)

func _step_toward(goal_tile: Vector2i) -> void:
	var path: Array = sector.find_path(current_tile, goal_tile)
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	if not sector.is_tile_walkable(next_tile):
		return
	_begin_step(next_tile)

func _step_away_from(target_tile: Vector2i) -> void:
	var dx: int = current_tile.x - target_tile.x
	var dy: int = current_tile.y - target_tile.y
	var step: Vector2i
	if abs(dx) >= abs(dy):
		step = Vector2i(int(sign(dx)), 0)
	else:
		step = Vector2i(0, int(sign(dy)))
	if step == Vector2i.ZERO:
		return
	var probe: Vector2i = current_tile + step
	if not sector.is_tile_walkable(probe):
		return
	_begin_step(probe)

func _begin_step(next_tile: Vector2i) -> void:
	_moving = true
	var target_world: Vector2 = sector.tile_to_world(next_tile)
	var step_seconds: float = TILE_STEP_PX / max(float(data.moveSpeed), 1.0)
	var t := create_tween()
	t.tween_property(self, "position", target_world, step_seconds) \
		.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func(): _on_step_complete(next_tile))

func _on_step_complete(arrived: Vector2i) -> void:
	current_tile = arrived
	_moving = false

func _find_engageable_target() -> Node2D:
	# Hero first — there are no deployed units in the survival build.
	# Units stay supported in code so existing data ports straight back
	# in once the hero-pet system lands.
	var best: Node2D = null
	var best_d: int = attack_range_tiles + 1
	for n in get_tree().get_nodes_in_group("hero"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if h.get("is_downed"):
			continue
		var d: int = sector.tile_distance(current_tile, h.current_tile)
		if d < best_d:
			best_d = d
			best = h
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		var d: int = sector.tile_distance(current_tile, u.current_tile)
		if d < best_d:
			best_d = d
			best = u
	return best

# ── Drawing ──────────────────────────────────────────────────────────────
func _draw() -> void:
	var size: Vector2 = data.size
	var rect := Rect2(-size * 0.5 + Vector2(0, -size.y * 0.5), size)
	draw_rect(rect, data.color_rgba, true)
	draw_rect(rect, DesignTokens.NIGHT_0, false, 2.0)
	var hp_ratio: float = 0.0 if hp_max == 0 else hp / hp_max
	var bar_y := -size.y - 6.0
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x, 3.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x * hp_ratio, 3.0), DesignTokens.hp_color(hp_ratio), true)
