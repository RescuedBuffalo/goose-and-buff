class_name BuffaloRig
extends Node2D
##
## Buffalo character rig (BUF-183 Phase 3 — frame-based, distance-driven).
##
## The walk cycle is driven by DISTANCE TRAVELLED, not a fixed FPS clock.
## This is the fix for "the walk feels weird" — a clock-driven cycle makes
## the feet slide/skate because the leg cadence is unrelated to how fast
## the body is actually moving across the ground. Tying frame advance to
## distance means one full 4-frame gait cycle == one stride length, so the
## planted foot visually stays put on the ground at any move speed.
##
## ─── Stride math ──────────────────────────────────────────────────────────
##
##   render_height   ~60px   (215px frame silhouette ≈ 200px × 0.30 scale)
##   stride_ratio     tunable (full gait travel as a fraction of height;
##                            ~0.8–1.0 reads natural, higher = longer
##                            "gliding" steps, lower = quicker shuffle)
##   stride_px       = render_height × stride_ratio   (ground px / cycle)
##   frames_per_cycle = 4
##   distance_per_frame = stride_px / frames_per_cycle
##
## Frame index = floor(distance_travelled / distance_per_frame) mod 4.
## Buffalo moveSpeed 12 studs/s × 12 px/stud = 144 px/s, so at
## stride_ratio 0.9 (stride_px ≈ 54) a full cycle takes ≈ 0.38s — and it
## stays correct if move speed ever changes (buffs, slows, charge).
##
## API:
##   set_movement(velocity_px_per_sec: Vector2)
##     Hero adapter calls this every physics tick with the actual world
##     velocity in px/s. Direction is quantized via CharacterDirection;
##     below the deadzone the rig idles on the planted pose.

const _ANIM_NAMES := {
	CharacterDirection.Direction.FRONT: "walk_front",
	CharacterDirection.Direction.BACK:  "walk_back",
	CharacterDirection.Direction.LEFT:  "walk_left",
	CharacterDirection.Direction.RIGHT: "walk_right",
}

const _FRAMES_PER_CYCLE := 4

# Index in each 4-frame walk loop to hold while idle. Frame 1 is the
# planted-feet pose across all 4 directions in the current sheet; frame
# 0 is mid-stride and reads as "frozen mid-walk."
const _IDLE_FRAME := 1

# Rendered character height in screen px (frame silhouette ≈ 200px at the
# AnimatedSprite2D's 0.30 scale). Used to derive a world-proportional
# stride length.
const _RENDER_HEIGHT_PX := 60.0

# Full-gait travel as a fraction of character height. THIS is the dial
# for walk feel: 0.8–1.0 is a natural stride; bump toward 1.4+ for a
# slower, longer-striding "glide"; drop toward 0.6 for a quick shuffle.
# Pure visual tuning — does not affect movement speed (that's hero.gd).
const _STRIDE_RATIO := 1.1

# Walk bob. Synced to the stride so the body lifts on each footfall
# rather than on an unrelated clock. Amplitude in screen px.
const _BOB_AMPLITUDE := 1.25

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing: int = CharacterDirection.Direction.FRONT
var _is_walking: bool = false
var _velocity_px: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _sprite_base_y: float = 0.0

# Ground px the character must travel to advance one frame, and to
# complete one full gait cycle. Computed once from the constants above.
var _stride_px: float = _RENDER_HEIGHT_PX * _STRIDE_RATIO
var _distance_per_frame: float = (_RENDER_HEIGHT_PX * _STRIDE_RATIO) / float(_FRAMES_PER_CYCLE)

func _ready() -> void:
	if anim_sprite == null:
		push_warning("[buffalo] no AnimatedSprite2D child found")
		return
	_sprite_base_y = anim_sprite.position.y
	# We drive frames manually off distance — never let SpriteFrames
	# auto-advance on its own clock.
	anim_sprite.stop()
	_apply_direction_animation()
	anim_sprite.frame = _IDLE_FRAME

## Hero adapter calls this every physics tick with world velocity (px/s).
func set_movement(velocity_px_per_sec: Vector2) -> void:
	_velocity_px = velocity_px_per_sec
	_is_walking = velocity_px_per_sec.length() >= 1.0
	var new_dir: int = CharacterDirection.from_velocity(velocity_px_per_sec)
	if new_dir >= 0 and new_dir != _facing:
		_facing = new_dir
		_apply_direction_animation()

func _apply_direction_animation() -> void:
	if anim_sprite == null:
		return
	var anim_name: String = _ANIM_NAMES.get(_facing, "walk_front")
	if anim_sprite.animation != StringName(anim_name):
		anim_sprite.animation = StringName(anim_name)

func _process(delta: float) -> void:
	if anim_sprite == null:
		return
	if _is_walking:
		_distance_travelled += _velocity_px.length() * delta
		var frame_idx: int = int(_distance_travelled / _distance_per_frame) % _FRAMES_PER_CYCLE
		anim_sprite.frame = frame_idx
		# Bob phase tracks the gait: two lifts per cycle (one per
		# footfall). cycle_phase 0→1 over one full stride.
		var cycle_phase: float = fmod(_distance_travelled / _stride_px, 1.0)
		var lift: float = absf(sin(cycle_phase * TAU)) * _BOB_AMPLITUDE
		anim_sprite.position.y = _sprite_base_y - lift
	else:
		# Idle: reset gait accumulator so the next walk starts from a
		# clean contact pose, hold the planted frame, drop the bob.
		_distance_travelled = 0.0
		anim_sprite.frame = _IDLE_FRAME
		if anim_sprite.position.y != _sprite_base_y:
			anim_sprite.position.y = _sprite_base_y
