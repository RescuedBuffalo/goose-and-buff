class_name CharacterRigController
extends Node2D
##
## Direction sprite-swap controller for a Skeleton2D character rig (BUF-183).
## Lives at the root of each character rig template (bipedal/quadruped) and
## is inherited by per-character scenes (Buffalo, Goose, Fox, Val, Wolf,
## Bear, Owl).
##
## ─── Lifecycle ────────────────────────────────────────────────────────────
##
## 1. Per-character scene instances the bipedal/quadruped template, then in
##    its _ready() calls `register_part(name, sprite)` for every visible
##    part (head, torso, hand_l, foot_r, ...) and `set_part_atlases(name,
##    {direction: AtlasTexture})` to provide art for each direction.
##
## 2. Hero/Enemy controller drives `set_direction(dir)` whenever the entity's
##    movement direction changes (CharacterDirection.from_velocity() decides).
##
## 3. set_direction triggers a per-part atlas swap. Missing directions fall
##    back to FRONT (with horizontal flip for LEFT/RIGHT) and a one-time
##    warning per direction so a half-finished rig still renders something.
##
## ─── Direction strategy ───────────────────────────────────────────────────
##
## Locked decision (per M3 plan, scenario-character-pipeline §5): sprite-swap
## on a single rig, NOT per-direction rigs and NOT 8-direction. A character
## faces one of {FRONT, BACK, LEFT, RIGHT} and parts swap atlases per facing.
##
## Initial Phase 3 art ships only FRONT-facing AtlasTextures. The fallback
## logic here means LEFT/RIGHT renders as flipped FRONT (acceptable —
## Buffalo's silhouette is roughly symmetric) and BACK renders as FRONT
## with a console warning until back-facing parts are authored.

const Direction = CharacterDirection.Direction

# Logical part name → Sprite2D node displaying it. Populated by the
# per-character scene during _ready via register_part().
var part_sprites: Dictionary = {}

# Logical part name → { direction_int: AtlasTexture }. Populated by the
# per-character scene during _ready via set_part_atlases().
var part_atlases: Dictionary = {}

# Tracks which directions have already triggered a fallback warning.
# Set semantics — _warned[dir] = true once, never warn again for that dir.
var _warned: Dictionary = {}

var current_direction: int = Direction.FRONT

@onready var skeleton: Skeleton2D = _find_skeleton()

func _ready() -> void:
	if skeleton == null:
		push_warning("[rig %s] no Skeleton2D child found; rig will not render bones" % name)

func _find_skeleton() -> Skeleton2D:
	# Templates put Skeleton2D as a direct child. Search one level deep so
	# per-character scenes that wrap the template still find it.
	for child in get_children():
		if child is Skeleton2D:
			return child
	for child in get_children():
		for grand in child.get_children():
			if grand is Skeleton2D:
				return grand
	return null

## Register a logical part name (e.g. "head", "hand_l") with the Sprite2D
## node that displays it. Idempotent — re-registering replaces the entry.
func register_part(part_name: String, sprite: Sprite2D) -> void:
	if sprite == null:
		push_warning("[rig %s] register_part(%s) got null sprite" % [name, part_name])
		return
	part_sprites[part_name] = sprite

## Provide direction-keyed AtlasTextures for a part. atlases is a dict of
## { CharacterDirection.Direction: AtlasTexture }. Missing directions are
## resolved at swap time via the FRONT-fallback logic.
func set_part_atlases(part_name: String, atlases: Dictionary) -> void:
	part_atlases[part_name] = atlases
	_apply_direction_to_part(part_name, current_direction)

## Update the rig's facing. Called by the Hero/Enemy adapter whenever
## CharacterDirection.from_velocity() returns a new direction.
func set_direction(dir: int) -> void:
	if dir < 0 or dir == current_direction:
		return
	current_direction = dir
	for part_name in part_sprites.keys():
		_apply_direction_to_part(part_name, dir)

func _apply_direction_to_part(part_name: String, dir: int) -> void:
	var sprite: Sprite2D = part_sprites.get(part_name)
	if sprite == null:
		return
	var atlases: Dictionary = part_atlases.get(part_name, {})
	if atlases.is_empty():
		return
	var tex: Texture2D = null
	var flip_h: bool = false
	var fell_back: bool = false
	if atlases.has(dir):
		tex = atlases[dir]
	elif dir == Direction.LEFT or dir == Direction.RIGHT:
		# Mirror FRONT for the missing side. LEFT = FRONT flipped,
		# RIGHT = FRONT unflipped (the asset's natural side); a
		# proper rigger override can flip the convention via direct
		# atlas assignment.
		tex = atlases.get(Direction.FRONT)
		flip_h = (dir == Direction.LEFT)
		fell_back = true
	else:
		# BACK falls back to FRONT until back-facing parts are authored.
		tex = atlases.get(Direction.FRONT)
		fell_back = true
	if tex == null:
		return
	sprite.texture = tex
	sprite.flip_h = flip_h
	if fell_back and not _warned.has(dir):
		_warned[dir] = true
		push_warning("[rig %s] direction %s missing part atlases for some parts; falling back to FRONT" % [name, CharacterDirection.name_for(dir)])
