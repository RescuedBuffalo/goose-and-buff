class_name BuffaloRig
extends Node2D
##
## Buffalo character rig (BUF-183 Phase 3 — frame-based).
##
## Drives the AnimatedSprite2D with a 4-direction walk loop sourced from
## buffalo_rigging_sheet.png (4 rows × 4 columns; each row is one
## direction's 4-frame walk cycle).
##
## API:
##   set_movement(velocity: Vector2)
##     Hero adapter calls this every frame with the current velocity.
##     Direction is derived via CharacterDirection.from_velocity; if the
##     velocity is below the deadzone, the character keeps its last facing
##     and pauses on the first frame of that direction (idle pose).

const _ANIM_NAMES := {
	CharacterDirection.Direction.FRONT: "walk_front",
	CharacterDirection.Direction.BACK:  "walk_back",
	CharacterDirection.Direction.LEFT:  "walk_left",
	CharacterDirection.Direction.RIGHT: "walk_right",
}

# Index in each 4-frame walk loop to hold while idle. Frame 1 is the
# planted-feet pose across all 4 directions in the current sheet; frame
# 0 is mid-stride and reads as "frozen mid-walk." Bump if a future sheet
# has its still pose at a different index.
const _IDLE_FRAME := 1

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing: int = CharacterDirection.Direction.FRONT
var _is_walking: bool = false

func _ready() -> void:
	if anim_sprite == null:
		push_warning("[buffalo] no AnimatedSprite2D child found")
		return
	_apply_animation_state()

## Called by the hero adapter every frame with the player's velocity.
## Updates facing direction (if velocity is non-trivial) and toggles
## between walking (animated) and idle (paused on frame 0) playback.
func set_movement(velocity: Vector2) -> void:
	var new_dir: int = CharacterDirection.from_velocity(velocity)
	var was_walking: bool = _is_walking
	_is_walking = velocity.length() >= 1.0
	if new_dir >= 0:
		# Only update facing when there's actual movement input — keep
		# the last facing if the player let go of keys mid-stride.
		if new_dir != _facing:
			_facing = new_dir
			_apply_animation_state()
			return
	if _is_walking != was_walking:
		_apply_animation_state()

func _apply_animation_state() -> void:
	if anim_sprite == null:
		return
	var anim_name: String = _ANIM_NAMES.get(_facing, "walk_front")
	if anim_sprite.animation != StringName(anim_name):
		anim_sprite.animation = StringName(anim_name)
	if _is_walking:
		anim_sprite.play()
	else:
		# Idle: snap to the most-still pose in the cycle. Frame 0 is mid-
		# stride (one foot forward); frame 1 is the closest to a planted
		# stance across all 4 directions in the user's sheet. Stop the
		# animation tick so we hold the still frame.
		anim_sprite.stop()
		anim_sprite.frame = _IDLE_FRAME
