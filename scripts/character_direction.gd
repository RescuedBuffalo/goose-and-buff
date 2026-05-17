class_name CharacterDirection
extends Resource
##
## Velocity → cardinal-direction enum mapping for the 4-direction sprite-swap
## rig pipeline (BUF-183). The locked direction strategy is sprite-swap on a
## single rig, NOT per-direction rigs and NOT 8-direction. Heroes face one of
## { FRONT, BACK, LEFT, RIGHT } and the rig controller swaps the AtlasTexture
## on each part slot when the direction changes.
##
## screen-axis convention (Godot 2D): +X = right, +Y = down. So a positive-Y
## velocity means walking toward the camera = FRONT. A negative-Y velocity =
## walking away from the camera = BACK.

enum Direction { FRONT, BACK, LEFT, RIGHT }

## Returns the appropriate Direction for a given velocity vector.
## Returns -1 if velocity is below the deadzone — the caller is expected
## to keep the last known direction in that case (don't snap to FRONT
## just because the player let go of the keys).
static func from_velocity(velocity: Vector2) -> int:
	if velocity.length() < 0.01:
		return -1
	# atan2 returns angle from +X axis. In screen coords:
	#   right = 0, down = +π/2, left = ±π, up = -π/2.
	# Quadrant boundaries split at ±π/4 and ±3π/4 to give equal 90° wedges
	# centered on each cardinal.
	var angle: float = velocity.angle()
	if abs(angle) < PI / 4.0:
		return Direction.RIGHT
	elif abs(angle) > 3.0 * PI / 4.0:
		return Direction.LEFT
	elif angle > 0.0:
		# +Y in Godot 2D = "down" on screen = walking toward camera.
		return Direction.FRONT
	else:
		return Direction.BACK

## Returns the direction name for logging / debug overlays.
static func name_for(dir: int) -> String:
	match dir:
		Direction.FRONT: return "FRONT"
		Direction.BACK: return "BACK"
		Direction.LEFT: return "LEFT"
		Direction.RIGHT: return "RIGHT"
		_: return "UNKNOWN"
