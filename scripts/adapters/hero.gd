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
const HeroVariants := preload("res://data/hero_variants.gd")
const MultiplayerDataClass := preload("res://data/multiplayer.gd")

const PIXELS_PER_STUD := 12.0

# BUF-181 build marker — bump per iteration so the editor console
# confirms which version of the portrait/shadow code is actually live.
# When you edit hero.gd or character_shadow.gd, bump this and the line
# in _ready() will print [hero v<N>] at run-start.
const _BUF_181_BUILD_MARKER := "BUF-181 v14 / BUF-183 Phase 3 (tail crop, no text artifact)"
# Toggle for verbose portrait/shadow logging. Leave on while M3 art
# pipeline placeholder is in flux; flip to false once Phase 3 rigs land.
const _DEBUG_PORTRAIT_LOG := true
# When true, writes the masked portrait PNG to user:// so you can open
# it in any image viewer and see exactly what the chroma-key produced.
# Path: %APPDATA%\Godot\app_userdata\<project>\masked_<hero_id>.png on Windows.
const _DEBUG_SAVE_MASKED_PNG := true
# When true, the procedural shadow renders bright magenta instead of
# soft black so it's unmistakably distinguishable from any halo or
# baked-in shadow in the source PNG.
const _DEBUG_SHADOW_TINT := false

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
# True once a portrait sprite is loaded. The portrait body + cursor
# already convey facing/swing direction, so the cream facing-notch
# placeholder is suppressed in this mode (it was scaffolding for the
# totem-icon era and reads as visual clutter against the body sprite).
var _is_using_portrait: bool = false

var sector: Node = null
@onready var sprite: Sprite2D = $Sprite
@onready var camera: Camera2D = $Camera
@onready var shadow: Node2D = $Shadow

# In-world character art (BUF-181 placeholder, BUF-183 rig source). Portraits
# live under design/ with the rigging sheets — they're the canonical
# eye-level front-facing character art. Totems are kept for HUD identity
# chips (see design_tokens.gd).
const CHARACTER_PORTRAIT_PATHS := {
	"Buffalo": "res://design/assets/characters/buffalo_character.png",
	"Goose": "res://design/assets/characters/goose_character.png",
	"Fox": "res://design/assets/characters/fox_character.png",
	"Val": "res://design/assets/characters/val_character.png",
}

# Skeleton2D rig scenes per character (BUF-183). Heroes with a rig
# entry get a real bone-driven character; heroes without one fall back
# to the chroma-keyed portrait sprite path. Phase 3 ships Buffalo's
# rig; Phase 4 will add Goose / Fox / Val / Wolf / Bear / Owl.
const RIG_SCENES := {
	"Buffalo": preload("res://scenes/characters/buffalo.tscn"),
}

# Live rig instance once attached. Kept around so we can call into it
# (set_direction, animation transitions) without re-querying the tree.
var _rig: Node2D = null

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

# Target on-screen height for the eye-level character against TILE_PIXELS=
# (64,32). 50px = ~1.5 iso tile-heights = "average human" against a ~3-tile
# forest tree (~96px). Trees:characters lands at ~1.9:1 which reads as a
# real forest rather than the previous 1.0:1 (tree-and-character-same-size).
# All four heroes share this height; per-hero overrides can come later if
# Goose-on-legs vs Fox-stocky needs differentiation. Enemy quadrupeds in
# Phase 4 will get their own targets (a Polar Bear should NOT be 50px).
const TARGET_CHARACTER_HEIGHT_PX := 50.0

func attach_sector(sector_node: Node) -> void:
	sector = sector_node

func set_hero(hero_id: String) -> void:
	hero_data = Heroes.ALL.get(hero_id, Heroes.Buffalo)

func _ready() -> void:
	if _DEBUG_PORTRAIT_LOG:
		# Build marker prints exactly once per hero spawn. Bumping
		# _BUF_181_BUILD_MARKER whenever this file or character_shadow.gd
		# changes is the in-engine confirmation that the editor is running
		# the latest code (vs. a cached / stale version).
		print("[hero ", hero_data.id, "] ", _BUF_181_BUILD_MARKER)
	hp_max = _stat_hp_max if _stat_hp_max > 0.0 else float(hero_data.baseHealth)
	hp = hp_max
	var move_speed: float = _stat_move_speed if _stat_move_speed > 0.0 else float(hero_data.moveSpeed)
	move_pixels_per_second = move_speed * PIXELS_PER_STUD
	GameState.set_hero_hp(hp, hp_max)
	add_to_group("hero")
	y_sort_enabled = true
	if sprite != null:
		sprite.y_sort_enabled = true
	# Pin the shadow to the absolute ground-shadow layer regardless of
	# the hero's own z (which is WORLD_ENTITIES = 0 today, but if we
	# ever bump a downed hero up a layer or apply a debug z to inspect
	# a single hero, the shadow should NOT follow). See RenderLayers.
	if shadow != null:
		shadow.z_as_relative = false
		shadow.z_index = RenderLayers.CHARACTER_SHADOW
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
	# Variant tint must be reapplied here — clearing modulate to white
	# would wipe BUF-129's per-run reskin on every revive. _apply_variant_tint
	# falls back to white when no variant is set.
	_apply_variant_tint()
	# PR #41 review: only the local hero feeds GameState — that singleton
	# drives the local HUD chip. Without this gate, a teammate's revive
	# (or dawn respawn at FALLEN_RESPAWN_HP_RATIO) overwrote the local
	# player's HP chip with the teammate's revived HP until the next
	# local damage event refreshed it. Mirrors the existing gate in
	# damage(), which has read this same lesson.
	if not is_remote_puppet:
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
	# main.gd._start_run() calls reset_hp() right after run-start, before
	# the player ever sees the hero. Without _apply_variant_tint here, the
	# downed-modulate-was-white reset stripped BUF-129's variant tint and
	# every run looked canonical. _apply_variant_tint handles the no-variant
	# case by setting modulate to white.
	_apply_variant_tint()
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
	if sprite == null:
		return
	# Tear down any previous rig (e.g., on hero swap mid-run).
	if _rig != null:
		_rig.queue_free()
		_rig = null
	# Skeleton2D rig path (BUF-183). If a rig scene exists for this hero,
	# attach it as a child and hide the placeholder portrait sprite.
	var rig_scene: PackedScene = RIG_SCENES.get(hero_data.id)
	if rig_scene != null:
		_attach_rig(rig_scene)
		_apply_variant_tint()
		return
	# Fallback to the chroma-keyed portrait path (legacy, used by heroes
	# whose rig hasn't been built yet — Goose/Fox/Val until Phase 4).
	var portrait_path: String = CHARACTER_PORTRAIT_PATHS.get(hero_data.id, "")
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var portrait: Texture2D = load(portrait_path)
		_apply_portrait(portrait)
		_apply_variant_tint()
		return
	var fallback_path: String = TOTEM_PATHS.get(hero_data.id, TOTEM_PATHS.Buffalo)
	var tex: Texture2D = load(fallback_path) if ResourceLoader.exists(fallback_path) else null
	if tex != null:
		sprite.texture = tex
		sprite.scale = TOTEM_SCALE.get(hero_data.id, Vector2(0.35, 0.35))
		sprite.position = Vector2.ZERO
		# Totems are HUD-style icons — center them on the hero origin (no
		# bottom-center anchor) so they read as a token, not a body.
		sprite.offset = Vector2.ZERO
		# Totems ship with proper alpha; chroma-key would break them. Clear
		# any portrait material that might be lingering from a previous
		# load.
		sprite.material = null
		_is_using_portrait = false
		_resize_shadow_for_sprite()
	else:
		sprite.texture = null
		queue_redraw()
	_apply_variant_tint()

# Sampled cream from the portrait corners — every portrait's parchment
# falls within ~10 RGB units of this. Used as the chroma-key key color
# during the alpha-mask preprocess.
const _PORTRAIT_CREAM_KEY := Vector3(0.988, 0.969, 0.910)
# RGB Euclidean-distance threshold under which a pixel counts as
# background. 0.12 catches the parchment + the anti-aliased near-cream
# halo pixels at silhouette edges without eating Buffalo's white-fur
# jacket trim, horn tips, or any other lightly-tinted body detail
# (those land ~0.13+ away from the parchment in RGB space).
const _PORTRAIT_KEY_THRESHOLD := 0.12
# The Scenario portraits ship with a soft baked drop-shadow under the
# character's feet — RGB ~(227, 215, 192) at peak, fading to cream at
# the edges. Distance from parchment is ~0.22, way past the body-safe
# threshold. We catch it with a wider threshold applied ONLY in the
# bottom band of the image, where the painted shadow lives. White-fur
# accents on Buffalo's jacket/horns are well above this band so the
# wider threshold doesn't reach them.
const _PORTRAIT_SHADOW_BAND_FRACTION := 0.20  # bottom 20% of source rows
const _PORTRAIT_SHADOW_KEY_THRESHOLD := 0.32  # catches painted-shadow tan

# Cache so we don't re-scan the same portrait every time a hero is
# instanced (run-start, respawn, remote puppet creation). Keyed by
# portrait path; values are dictionaries:
#   { "texture": Texture2D, "bbox": Rect2i }
# bbox is the content bounding box (alpha > 0) in source-texture pixel
# coords, used by _apply_portrait to anchor the character's feet at the
# hero origin and scale based on content height (not full texture height,
# which includes empty rows where the cream + painted shadow used to be).
# Phase 3 rigs replace this whole pipeline.
static var _portrait_cache: Dictionary = {}

func _attach_rig(rig_scene: PackedScene) -> void:
	# Hide the placeholder portrait Sprite2D — the rig replaces it. Sprite
	# stays in the scene tree (the existing _draw / damage / variant code
	# still references it), it just renders nothing.
	sprite.texture = null
	sprite.material = null
	_is_using_portrait = true  # suppresses the cream facing-notch placeholder
	_rig = rig_scene.instantiate()
	add_child(_rig)
	# Rig root anchors at Hero's origin (0,0). The Skeleton2D origin is
	# at the character's feet per BUF-181 bottom-center convention, so
	# adding the rig as a child of Hero (positioned at the hero's
	# current_tile world position) lands the feet on the tile.
	_resize_shadow_for_sprite()
	if _DEBUG_PORTRAIT_LOG:
		print("[hero ", hero_data.id, "] rig attached: ", rig_scene.resource_path)

func _apply_portrait(src: Texture2D) -> void:
	# Anchor the portrait so the BOTTOM OF CONTENT (lowest opaque row,
	# i.e. the character's feet) lands at the hero origin, and scale so
	# that the content occupies exactly TARGET_CHARACTER_HEIGHT_PX rendered
	# pixels in height. Scaling by full texture height instead of content
	# height would render the character undersized whenever the source PNG
	# has empty padding rows (e.g. the cream/painted-shadow strip below
	# the character that flood-fill just stripped) — causing the visible
	# "floating" gap between the body and the procedural shadow.
	var portrait_path: String = CHARACTER_PORTRAIT_PATHS.get(hero_data.id, "")
	if _DEBUG_PORTRAIT_LOG:
		print("[hero ", hero_data.id, "] portrait path=", portrait_path, " src=", src.get_width(), "x", src.get_height())
	var data: Dictionary = _get_portrait_data(portrait_path, src)
	var tex: Texture2D = data.get("texture")
	var bbox: Rect2i = data.get("bbox", Rect2i(0, 0, tex.get_width(), tex.get_height()))
	sprite.texture = tex
	var tex_w: float = float(tex.get_width())
	var tex_h: float = float(tex.get_height())
	var content_h: float = max(float(bbox.size.y), 1.0)
	var auto_scale: float = TARGET_CHARACTER_HEIGHT_PX / content_h
	sprite.scale = Vector2(auto_scale, auto_scale)
	sprite.position = Vector2.ZERO
	# Sprite2D centered=true draws texture pixel (px, py) at local position
	# (px - tex_w/2 + offset.x, py - tex_h/2 + offset.y) (pre-scale). To put
	# the bottom edge of the lowest opaque row (Rect2i exclusive end y) at
	# local y=0, and the content's horizontal center at x=0, set:
	var content_center_x: float = float(bbox.position.x) + float(bbox.size.x) * 0.5
	var content_bottom_y: float = float(bbox.position.y + bbox.size.y)
	sprite.offset = Vector2(tex_w * 0.5 - content_center_x, tex_h * 0.5 - content_bottom_y)
	# Pre-processed alpha mask gives clean edges through GPU filtering;
	# no shader material needed.
	sprite.material = null
	_is_using_portrait = true
	_resize_shadow_for_sprite()
	if _DEBUG_PORTRAIT_LOG:
		print("[hero ", hero_data.id, "] bbox=", bbox, " content_h=%.0fpx" % content_h, " auto_scale=%.4f" % auto_scale)
		print("[hero ", hero_data.id, "] sprite scale=", sprite.scale, " offset=", sprite.offset)

func _get_portrait_data(path: String, src: Texture2D) -> Dictionary:
	# Three-stage CPU pipeline runs once per portrait, then cached:
	#
	#   0. SHORT CIRCUIT: if the source PNG already has alpha (corner
	#      pixel transparent), skip everything below — the artist has
	#      pre-cut the background and we can use the texture as-is.
	#
	#   1. CREAM CLASSIFICATION: per pixel, decide cream-vs-body using a
	#      band-aware distance test. Top 80% uses a tight 0.12 threshold
	#      (body-safe — won't eat horn-interior cream or jacket-fur trim).
	#      Bottom 20% uses a wider 0.32 threshold to catch the soft baked
	#      drop-shadow Scenario portraits ship with.
	#
	#   2. EDGE-REACHABLE FLOOD FILL: BFS from every cream pixel on the
	#      image border, expanding through cream-classified neighbors.
	#      Pixels marked = background. Horn-interior cream is surrounded
	#      by brown outline so BFS never reaches it; it stays opaque.
	#      The painted shadow is contiguous with the surrounding cream so
	#      BFS reaches it; it gets masked.
	#
	#   3. RGB ALPHA-BLEED: every transparent pixel that has an opaque
	#      neighbor takes its neighbor's RGB (alpha stays 0). Kills the
	#      bilinear-filter cream/black halo at the silhouette edge.
	if path != "" and _portrait_cache.has(path):
		if _DEBUG_PORTRAIT_LOG:
			print("[hero ", hero_data.id, "] portrait cache HIT for ", path)
		return _portrait_cache[path]
	if src == null:
		return {"texture": null, "bbox": Rect2i()}
	var t0_us := Time.get_ticks_usec()
	var src_img: Image = src.get_image()
	if src_img == null:
		return {"texture": src, "bbox": Rect2i(0, 0, src.get_width(), src.get_height())}
	if src_img.is_compressed():
		src_img.decompress()
	src_img.convert(Image.FORMAT_RGBA8)
	var w: int = src_img.get_width()
	var h: int = src_img.get_height()

	# Stage 0: transparent source detection. If the four image corners
	# are already transparent the artist has done our work for us.
	if (src_img.get_pixel(0, 0).a < 0.5
			and src_img.get_pixel(w - 1, 0).a < 0.5
			and src_img.get_pixel(0, h - 1).a < 0.5
			and src_img.get_pixel(w - 1, h - 1).a < 0.5):
		var pre_bbox: Rect2i = _content_bbox(src_img, w, h)
		if _DEBUG_PORTRAIT_LOG:
			print("[hero ", hero_data.id, "] source already transparent (", w, "x", h, ") bbox=", pre_bbox, " — chroma-key bypassed")
		var pre_data: Dictionary = {"texture": src, "bbox": pre_bbox}
		if path != "":
			_portrait_cache[path] = pre_data
		return pre_data

	var body_threshold_sq: float = _PORTRAIT_KEY_THRESHOLD * _PORTRAIT_KEY_THRESHOLD
	var shadow_threshold_sq: float = _PORTRAIT_SHADOW_KEY_THRESHOLD * _PORTRAIT_SHADOW_KEY_THRESHOLD
	var shadow_band_y: int = int(h * (1.0 - _PORTRAIT_SHADOW_BAND_FRACTION))
	var n: int = w * h

	# Stage 1: classify every pixel as cream (1) or body (0). Stored in a
	# flat byte array indexed by y*w+x for fast BFS access.
	var is_cream := PackedByteArray()
	is_cream.resize(n)
	for y in h:
		var threshold_sq: float = shadow_threshold_sq if y >= shadow_band_y else body_threshold_sq
		var row_base: int = y * w
		for x in w:
			var c: Color = src_img.get_pixel(x, y)
			var dr: float = c.r - _PORTRAIT_CREAM_KEY.x
			var dg: float = c.g - _PORTRAIT_CREAM_KEY.y
			var db: float = c.b - _PORTRAIT_CREAM_KEY.z
			if dr * dr + dg * dg + db * db < threshold_sq:
				is_cream[row_base + x] = 1

	# Stage 2: BFS flood fill from border cream pixels. mask[i] = 1 means
	# "edge-reachable cream → make transparent." Interior cream (horn fill,
	# eyes, etc) stays 0 and remains opaque.
	var mask := PackedByteArray()
	mask.resize(n)
	var queue := PackedInt32Array()
	# Seed: top + bottom rows
	for x in w:
		var top_idx: int = x
		if is_cream[top_idx] == 1 and mask[top_idx] == 0:
			mask[top_idx] = 1
			queue.append(top_idx)
		var bot_idx: int = (h - 1) * w + x
		if is_cream[bot_idx] == 1 and mask[bot_idx] == 0:
			mask[bot_idx] = 1
			queue.append(bot_idx)
	# Seed: left + right columns
	for y in h:
		var left_idx: int = y * w
		if is_cream[left_idx] == 1 and mask[left_idx] == 0:
			mask[left_idx] = 1
			queue.append(left_idx)
		var right_idx: int = y * w + (w - 1)
		if is_cream[right_idx] == 1 and mask[right_idx] == 0:
			mask[right_idx] = 1
			queue.append(right_idx)
	# Manual FIFO with head pointer (avoids PackedInt32Array.pop which is slow).
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var iy: int = idx / w
		var ix: int = idx - iy * w
		# 4-neighbors are sufficient for a connectivity flood fill.
		if ix > 0:
			var ni: int = idx - 1
			if is_cream[ni] == 1 and mask[ni] == 0:
				mask[ni] = 1
				queue.append(ni)
		if ix < w - 1:
			var ni2: int = idx + 1
			if is_cream[ni2] == 1 and mask[ni2] == 0:
				mask[ni2] = 1
				queue.append(ni2)
		if iy > 0:
			var ni3: int = idx - w
			if is_cream[ni3] == 1 and mask[ni3] == 0:
				mask[ni3] = 1
				queue.append(ni3)
		if iy < h - 1:
			var ni4: int = idx + w
			if is_cream[ni4] == 1 and mask[ni4] == 0:
				mask[ni4] = 1
				queue.append(ni4)

	# Apply the mask: zero alpha (RGB temporary mid-grey for stage 3 to
	# overwrite). We mutate src_img in place; it was decompressed/converted
	# above and isn't shared.
	var keyed_count: int = 0
	var shadow_keyed_count: int = 0
	for y in h:
		var row_base2: int = y * w
		for x in w:
			if mask[row_base2 + x] == 1:
				src_img.set_pixel(x, y, Color(0.5, 0.5, 0.5, 0))
				keyed_count += 1
				if y >= shadow_band_y:
					shadow_keyed_count += 1

	# Stage 3: RGB alpha-bleed. For each transparent pixel with an opaque
	# neighbor, copy the neighbor's RGB so bilinear filtering produces
	# body-colored partial-alpha edges instead of black/cream halo.
	var bleed_count: int = 0
	for y in h:
		for x in w:
			var oc: Color = src_img.get_pixel(x, y)
			if oc.a > 0.01:
				continue
			var bleed: Color = _find_opaque_neighbor_rgb(src_img, x, y, w, h)
			if bleed.a > 0.5:
				src_img.set_pixel(x, y, Color(bleed.r, bleed.g, bleed.b, 0))
				bleed_count += 1

	var masked: ImageTexture = ImageTexture.create_from_image(src_img)
	var bbox: Rect2i = _content_bbox(src_img, w, h)
	var data: Dictionary = {"texture": masked, "bbox": bbox}
	if path != "":
		_portrait_cache[path] = data
	var elapsed_ms := (Time.get_ticks_usec() - t0_us) / 1000.0
	if _DEBUG_PORTRAIT_LOG:
		var keyed_pct: float = 100.0 * float(keyed_count) / float(max(1, n))
		print("[hero ", hero_data.id, "] mask built in %.0fms: %d/%d pixels keyed (%.1f%%, %d in shadow band), %d edge bleed, queue size %d, bbox=" % [elapsed_ms, keyed_count, n, keyed_pct, shadow_keyed_count, bleed_count, queue.size()], bbox)
	if _DEBUG_SAVE_MASKED_PNG:
		var out_path: String = "user://masked_%s.png" % hero_data.id
		var save_err: int = src_img.save_png(out_path)
		var abs_path: String = ProjectSettings.globalize_path(out_path)
		print("[hero ", hero_data.id, "] saved masked PNG -> ", abs_path, " (err=", save_err, ")")
	return data

func _content_bbox(img: Image, w: int, h: int) -> Rect2i:
	# Tightest rectangle covering all opaque pixels (alpha > 0.5). Used for
	# anchor + scale of the rendered sprite — we want to ground the
	# character's actual feet at the hero origin and size them by their
	# real silhouette, not by the source PNG canvas.
	var min_x: int = w
	var max_x: int = -1
	var min_y: int = h
	var max_y: int = -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	if max_x < 0:
		# Fully transparent image — fall back to full canvas to avoid
		# zero-size rect downstream.
		return Rect2i(0, 0, w, h)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _find_opaque_neighbor_rgb(img: Image, x: int, y: int, w: int, h: int) -> Color:
	# Returns the RGB of the first 8-neighbor opaque pixel found, with
	# alpha=1 to signal "found." Returns alpha=0 if no opaque neighbor
	# exists. Nesting tight to keep this hot loop fast.
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var nc: Color = img.get_pixel(nx, ny)
			if nc.a > 0.5:
				return Color(nc.r, nc.g, nc.b, 1.0)
	return Color(0, 0, 0, 0)

func _resize_shadow_for_sprite() -> void:
	if shadow == null:
		return
	# Shadow sized off the character's apparent FOOT footprint, not the
	# full sprite width — portraits include arm/horn/tail extents that
	# shouldn't cast a body-sized shadow on the ground. 18% of rendered
	# sprite width keeps the shadow comfortably inside one iso tile face
	# (TILE_PIXELS = 64x32) so it doesn't spill into neighbors. Vertical
	# squash to ~30% gives a flat ground-disk read under the tilt-feel
	# zoom rather than a floating circle.
	var rx: float = 12.0
	var ry: float = 4.0
	if sprite != null and sprite.texture != null:
		var rendered_w: float = float(sprite.texture.get_width()) * sprite.scale.x
		rx = clamp(rendered_w * 0.18, 6.0, 22.0)
		ry = max(rx * 0.30, 3.0)
	shadow.set("radius_x", rx)
	shadow.set("radius_y", ry)
	# Slightly softer alpha than the initial pass — 0.28 reads as ground
	# contact without dominating against the iso terrain colors.
	shadow.set("alpha", 0.28)
	# Debug tint flips the procedural shadow to bright magenta so it can
	# be visually distinguished from any baked-in shadow / chroma-key
	# halo coming from the source PNG.
	if _DEBUG_SHADOW_TINT:
		shadow.set("color_rgb", Color(1, 0, 1))
		shadow.set("alpha", 0.85)
	else:
		shadow.set("color_rgb", Color(0, 0, 0))
	shadow.queue_redraw()
	if _DEBUG_PORTRAIT_LOG:
		print("[hero ", hero_data.id, "] shadow rx=%.1f ry=%.1f alpha=%.2f tint=%s" % [rx, ry, float(shadow.get("alpha")), str(shadow.get("color_rgb"))])

func _apply_variant_tint() -> void:
	# BUF-129: variants ship as palette tints until the M3 portrait pipeline
	# lands. Run-start picks one of ~4 looks per hero and stores the id on
	# save_state.current_variants[hero_id]; we read it here and modulate
	# the sprite. Empty variant_id (assets-not-authored, save-from-pre-M2,
	# Val) → no-op, sprite stays canonical.
	if sprite == null:
		return
	var variant_id: String = SaveIo.current_variant(hero_data.id)
	if variant_id.is_empty():
		sprite.modulate = Color(1, 1, 1, 1)
		return
	sprite.modulate = HeroVariants.tint_for(variant_id)

func _draw() -> void:
	# Downed/fallen heroes get the kneel marker even with a sprite — it's
	# a bold timer ring above the totem so teammates can read "this hero
	# needs help" from across the world.
	if is_downed:
		_draw_downed_overlay()
		return
	if sprite != null and sprite.texture != null:
		# Portrait body + cursor already show facing/swing direction —
		# the notch is only useful for the totem-icon fallback.
		if not _is_using_portrait:
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
	# Small "AI" tag near the hero — voice rule: the badge is two
	# letters, no emoji. Renders for both the local view of a remote AI
	# placeholder and the host's view of a dropped client.
	# Position depends on anchor: portrait sprites are bottom-center
	# anchored so the head sits high above the origin; totem icons are
	# centered on the origin. Keep the badge legible relative to the
	# rendered character either way.
	var font: Font = ThemeDB.fallback_font
	var label: String = "AI"
	var color := DesignTokens.FG_3
	var pos := Vector2(-8, 28) if not _is_using_portrait else Vector2(-8, -TARGET_CHARACTER_HEIGHT_PX - 6)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, color)

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
