extends Node2D
##
## Hero adapter — WASD-controlled Buffalo with cursor-facing for the
## survival rebuild. The wave-defense build click-to-moved on the tile
## grid; survival reframes the hero as a walking presence in the world,
## so input switches to direction-of-press movement and click is reserved
## for combat swing.
##
## Movement is pixel-grain (smooth diagonal feel, free-form motion) but
## current_tile is updated each frame from the rounded position so the
## tile-aware systems (gather, build, enemy targeting) keep their
## tile-grain contract.

const Heroes := preload("res://data/heroes.gd")
const Sectors := preload("res://data/sectors.gd")
const MultiplayerDataClass := preload("res://data/multiplayer.gd")

const PIXELS_PER_STUD := 12.0

signal hero_downed()
signal hero_fallen()
signal tile_changed(new_tile: Vector2i)
signal facing_changed(new_facing: Vector2)

var hero_data: Dictionary = Heroes.Buffalo
var hp_max: float = 0.0
var hp: float = 0.0
var is_downed: bool = false
# Fallen = downed timer expired and no revive landed. Hero waits at the
# lodge until dawn, then respawns at FALLEN_RESPAWN_HP_RATIO. is_downed
# remains true while is_fallen is true so combat/input gates stay closed.
var is_fallen: bool = false
# Revive timer ticks down only while downed. When it hits 0 and the
# hero hasn't been revived, they transition to fallen.
var downed_seconds_remaining: float = 0.0
# Revive-in-progress accumulator. Set by main.gd when a teammate stands
# in range holding R; reset when they release. The hero adapter just
# carries the value so the HUD overlay can read it without main.gd
# needing to push it via signal.
var revive_progress_seconds: float = 0.0
var move_pixels_per_second: float = 0.0
var current_tile: Vector2i = Sectors.SPAWN_TILE
var facing: Vector2 = Vector2.RIGHT
# Multiplayer puppet support. When false, this hero is the local player
# and reads input + drives _physics_process movement. When true, this is
# a remote teammate's puppet and position is overwritten by replication
# RPCs at the configured sync rate.
var is_remote_puppet: bool = false
# AI placeholder behavior — set when the owning peer disconnects and the
# hero needs to keep "playing" until they reconnect or the run ends.
var is_ai_placeholder: bool = false
# Cached identity for HUD lookups + telemetry.
var peer_id: int = 0

# Effective-stat overrides (BUF-147). main.gd calls apply_stats() at
# run-start with the resolved values from stat_system.effective_stats.
# Defaults pull from the hero's base values in heroes.gd via _ready.
var _stat_hp_max: float = -1.0
var _stat_move_speed: float = -1.0

var sector: Node = null
@onready var sprite: Sprite2D = $Sprite
@onready var camera: Camera2D = $Camera

const TOTEM_PATHS := {
	"Buffalo": "res://assets/totems/buffalo.png",
	"Goose": "res://assets/totems/goose.svg",
	"Fox": "res://assets/totems/fox.svg",
}

const TOTEM_SCALE := {
	"Buffalo": Vector2(0.30, 0.30),
	"Goose": Vector2(0.40, 0.40),
	"Fox": Vector2(0.40, 0.40),
}

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func set_hero(hero_id: String) -> void:
	hero_data = Heroes.ALL.get(hero_id, Heroes.Buffalo)

func _ready() -> void:
	hp_max = _stat_hp_max if _stat_hp_max > 0.0 else float(hero_data.baseHealth)
	hp = hp_max
	var move_speed: float = _stat_move_speed if _stat_move_speed > 0.0 else float(hero_data.moveSpeed)
	move_pixels_per_second = move_speed * PIXELS_PER_STUD
	GameState.set_hero_hp(hp, hp_max)
	add_to_group("hero")
	y_sort_enabled = true
	if sprite != null:
		sprite.y_sort_enabled = true
	_load_sprite()
	if sector != null:
		current_tile = Sectors.SPAWN_TILE
		position = sector.tile_to_world(current_tile)
		_apply_camera_limits()

func _apply_camera_limits() -> void:
	# Constrain the camera to the world's iso bounding box so panning
	# along the south/north edges doesn't reveal void. Iso tile world
	# positions form a diamond — compute the four corner world positions
	# and use the min/max for the rectangular camera limit.
	if camera == null or sector == null:
		return
	var grid: Vector2i = Sectors.TILE_GRID_SIZE
	var corners: Array[Vector2] = [
		sector.tile_to_world(Vector2i(0, 0)),
		sector.tile_to_world(Vector2i(grid.x - 1, 0)),
		sector.tile_to_world(Vector2i(0, grid.y - 1)),
		sector.tile_to_world(Vector2i(grid.x - 1, grid.y - 1)),
	]
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for c in corners:
		min_x = min(min_x, c.x)
		max_x = max(max_x, c.x)
		min_y = min(min_y, c.y)
		max_y = max(max_y, c.y)
	# Pad by half a tile so the very edge tile still has some breathing
	# room around it visually.
	var pad_x: float = float(Sectors.TILE_PIXELS.x) * 0.5
	var pad_y: float = float(Sectors.TILE_PIXELS.y) * 0.5
	camera.limit_left = int(min_x - pad_x)
	camera.limit_right = int(max_x + pad_x)
	camera.limit_top = int(min_y - pad_y)
	camera.limit_bottom = int(max_y + pad_y)

func _physics_process(delta: float) -> void:
	if sector == null:
		return
	# Freeze movement + facing once the run ends. main.gd's _process
	# already gates the cycle/wave/combat ticks on this; mirror it here
	# so the hero doesn't drift behind the end-screen scrim.
	if GameState.phase == GameState.Phase.RUN_ENDED or GameState.phase == GameState.Phase.RUN_COMPLETE:
		return
	# Downed-timer countdown ticks regardless of authority — it's the
	# same on every peer because the host broadcasts the down/revive
	# transitions and clients run the visual countdown locally for HUD
	# display. The actual fallen transition fires only on the host (see
	# main.gd) so the puppet branch here just renders.
	if is_downed and not is_fallen:
		downed_seconds_remaining = max(0.0, downed_seconds_remaining - delta)
	if is_downed:
		return
	# Remote puppets and AI placeholders don't read local input. Their
	# pose is overwritten by replication RPCs (apply_remote_pose) on the
	# configured cadence; they still y-sort + draw normally.
	if is_remote_puppet or is_ai_placeholder:
		return
	# WASD → direct screen-cardinal movement. The Hades / Stardew
	# convention: pressing "up" walks the hero straight up on the
	# screen, regardless of how the iso tile axes are oriented. Tile
	# coords update as a side-effect when the hero crosses boundaries.
	var input_dir: Vector2 = _read_input_direction()
	if input_dir != Vector2.ZERO:
		var step: Vector2 = input_dir * move_pixels_per_second * delta
		var proposed: Vector2 = position + step
		var proposed_tile: Vector2i = sector.world_to_tile(proposed)
		if sector.is_tile_walkable(proposed_tile):
			position = proposed
		else:
			# Slide along the unblocked axis if any — feels less sticky
			# than a hard stop into corners.
			var dx_only: Vector2 = position + Vector2(step.x, 0)
			var dy_only: Vector2 = position + Vector2(0, step.y)
			if sector.is_tile_walkable(sector.world_to_tile(dx_only)):
				position = dx_only
			elif sector.is_tile_walkable(sector.world_to_tile(dy_only)):
				position = dy_only
		var new_tile: Vector2i = sector.world_to_tile(position)
		if new_tile != current_tile:
			current_tile = new_tile
			tile_changed.emit(current_tile)
	# Face toward cursor every frame so the swing arc reads honestly.
	# Falling back to last facing if the cursor is somehow on top of us.
	var mouse_world: Vector2 = get_global_mouse_position()
	var to_cursor: Vector2 = mouse_world - position
	if to_cursor.length_squared() > 4.0:
		var new_facing: Vector2 = to_cursor.normalized()
		if new_facing != facing:
			facing = new_facing
			facing_changed.emit(facing)

func apply_remote_pose(new_pos: Vector2, new_facing: Vector2) -> void:
	# Replication adapter calls this with the host-rebroadcast position
	# for remote heroes. Direct write — at 10Hz over a 1080p viewport the
	# eye barely catches the lack of interpolation, and the local hero
	# always has zero perceived lag because its own _physics_process
	# drives it.
	position = new_pos
	if new_facing.length_squared() > 0.01 and new_facing != facing:
		facing = new_facing
		facing_changed.emit(facing)
	if sector != null:
		var new_tile: Vector2i = sector.world_to_tile(position)
		if new_tile != current_tile:
			current_tile = new_tile
			tile_changed.emit(current_tile)

func set_remote_puppet(remote: bool) -> void:
	is_remote_puppet = remote
	# Remote puppets shouldn't carry the local viewport's camera. The
	# scene leaves the Camera2D node parented underneath, so toggling
	# is_current keeps it in the tree but stops it from being the active
	# camera when the local hero respawns next to it.
	if camera != null:
		camera.enabled = not remote and not is_ai_placeholder

func set_ai_placeholder(active: bool) -> void:
	is_ai_placeholder = active
	if camera != null:
		camera.enabled = not is_remote_puppet and not is_ai_placeholder
	queue_redraw()

func apply_revive(hp_ratio: float) -> void:
	# Snap the hero out of downed/fallen and refill HP to the supplied
	# ratio. Replication broadcasts this so every peer sees the same
	# transition.
	is_downed = false
	is_fallen = false
	downed_seconds_remaining = 0.0
	revive_progress_seconds = 0.0
	hp = clamp(hp_ratio, 0.05, 1.0) * hp_max
	if sprite != null:
		sprite.modulate = Color(1, 1, 1, 1)
	GameState.set_hero_hp(hp, hp_max)
	queue_redraw()

func apply_fallen() -> void:
	# Downed timer expired without a revive. The hero stays kneeling at
	# the lodge until dawn, then respawns at FALLEN_RESPAWN_HP_RATIO.
	is_fallen = true
	is_downed = true
	revive_progress_seconds = 0.0
	if sprite != null:
		sprite.modulate = Color(0.4, 0.2, 0.2, 0.5)
	hero_fallen.emit()
	queue_redraw()

func reset_position() -> void:
	current_tile = Sectors.SPAWN_TILE
	if sector != null:
		position = sector.tile_to_world(current_tile)
	tile_changed.emit(current_tile)

func reset_hp() -> void:
	is_downed = false
	is_fallen = false
	downed_seconds_remaining = 0.0
	revive_progress_seconds = 0.0
	hp = hp_max
	if sprite != null:
		sprite.modulate = Color(1, 1, 1, 1)
	GameState.set_hero_hp(hp, hp_max)
	queue_redraw()

func apply_stats(stat_hp_max: float, stat_move_speed: float) -> void:
	# Called by main.gd after stat_system computes effective_stats. Safe
	# to call before _ready (cached and applied there) or after (mutates
	# hp_max + move speed in place; full HP refilled).
	_stat_hp_max = stat_hp_max
	_stat_move_speed = stat_move_speed
	if hp_max > 0.0:
		hp_max = stat_hp_max
		hp = hp_max
		move_pixels_per_second = stat_move_speed * PIXELS_PER_STUD
		GameState.set_hero_hp(hp, hp_max)
		queue_redraw()

func revive() -> void:
	reset_hp()

func damage(amount: float) -> void:
	if is_downed:
		return
	hp = max(0.0, hp - amount)
	# Only the local hero's HP feeds GameState — that singleton drives
	# the local HUD chip, which is per-peer. Remote heroes update their
	# own visual state but don't overwrite the local HUD's HP read.
	if not is_remote_puppet:
		GameState.set_hero_hp(hp, hp_max)
	if hp <= 0.0:
		is_downed = true
		downed_seconds_remaining = MultiplayerDataClass.DOWNED_TIMER_SECONDS
		revive_progress_seconds = 0.0
		if sprite != null:
			sprite.modulate = Color(1.0, 0.3, 0.3, 0.65)
		hero_downed.emit()
	queue_redraw()

func spawn_tile() -> Vector2i:
	return Sectors.SPAWN_TILE

# ── Input ────────────────────────────────────────────────────────────

func _read_input_direction() -> Vector2:
	# Action names are registered in project.godot (move_up/down/left/right).
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	return dir

# ── Sprite ───────────────────────────────────────────────────────────

func _load_sprite() -> void:
	var path: String = TOTEM_PATHS.get(hero_data.id, TOTEM_PATHS.Buffalo)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if sprite == null:
		return
	if tex != null:
		sprite.texture = tex
		sprite.scale = TOTEM_SCALE.get(hero_data.id, Vector2(0.35, 0.35))
		sprite.position = Vector2.ZERO
	else:
		sprite.texture = null
		queue_redraw()

func _draw() -> void:
	# Downed/fallen heroes get the kneel marker even with a sprite — it's
	# a bold timer ring above the totem so teammates can read "this hero
	# needs help" from across the world.
	if is_downed:
		_draw_downed_overlay()
		return
	if sprite != null and sprite.texture != null:
		_draw_facing_notch()
		_draw_ai_badge_if_needed()
		return
	var fill: Color = DesignTokens.core_color(hero_data.id)
	draw_circle(Vector2.ZERO, 18.0, fill)
	_draw_facing_notch()
	_draw_ai_badge_if_needed()

func _draw_downed_overlay() -> void:
	# Red kneel cross + circular timer ring above the hero. Ring shrinks
	# clockwise as downed_seconds_remaining ticks down so teammates can
	# eyeball "how long do they have left?" without checking a HUD chip.
	var fill: Color = Color(0.5, 0.1, 0.1) if not is_fallen else Color(0.3, 0.05, 0.05)
	draw_circle(Vector2.ZERO, 18.0, fill)
	draw_line(Vector2(-10, -10), Vector2(10, 10), Color(1, 0.1, 0.1, 0.9), 3.0)
	draw_line(Vector2(-10, 0), Vector2(10, -20), Color(1, 0.1, 0.1, 0.9), 3.0)
	if not is_fallen and downed_seconds_remaining > 0.0:
		var ratio: float = clamp(downed_seconds_remaining / MultiplayerDataClass.DOWNED_TIMER_SECONDS, 0.0, 1.0)
		_draw_arc_ring(Vector2(0, -32), 12.0, ratio, DesignTokens.HP_WARN)
	if revive_progress_seconds > 0.0:
		var ratio: float = clamp(revive_progress_seconds / MultiplayerDataClass.REVIVE_HOLD_SECONDS, 0.0, 1.0)
		_draw_arc_ring(Vector2(0, -32), 14.0, ratio, DesignTokens.HP_FULL)
	if is_fallen:
		var label_color: Color = DesignTokens.FG_2
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-26, -42), "fallen", HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, label_color)

func _draw_arc_ring(center: Vector2, radius: float, ratio: float, color: Color) -> void:
	# Clockwise arc from 12 o'clock proportional to ratio. Approximated
	# with a polyline since draw_arc uses point counts not pixel widths.
	var points := PackedVector2Array()
	var segments: int = 20
	var end_segments: int = int(round(float(segments) * ratio))
	for i in range(end_segments + 1):
		var theta: float = -PI / 2.0 + (TAU * float(i) / float(segments))
		points.append(center + Vector2(cos(theta), sin(theta)) * radius)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, 2.5)

func _draw_ai_badge_if_needed() -> void:
	if not is_ai_placeholder:
		return
	# Small "AI" tag below the hero — voice rule: the badge is two
	# letters, no emoji. Renders for both the local view of a remote AI
	# placeholder and the host's view of a dropped client.
	var font: Font = ThemeDB.fallback_font
	var label: String = "AI"
	var color := DesignTokens.FG_3
	draw_string(font, Vector2(-8, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, color)

func _draw_facing_notch() -> void:
	# Tiny indicator at the hero's feet pointing where they're facing —
	# helps make swing direction legible while sprites are placeholder.
	var tip: Vector2 = facing.normalized() * 22.0
	var perp := Vector2(-facing.y, facing.x).normalized() * 4.0
	var notch_color := Color(DesignTokens.PARCHMENT_0.r, DesignTokens.PARCHMENT_0.g, DesignTokens.PARCHMENT_0.b, 0.85)
	draw_polygon(
		PackedVector2Array([tip, tip - facing * 8.0 + perp, tip - facing * 8.0 - perp]),
		PackedColorArray([notch_color, notch_color, notch_color]),
	)
