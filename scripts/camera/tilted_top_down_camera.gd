class_name TiltedTopDownCamera
extends Camera2D
##
## Tilted top-down camera (M3 BUF-181). The world is rendered straight-on;
## the "tilt feel" comes from a vertical zoom squash + Y-sort + bottom-
## center sprite anchoring on characters. Not isometric, not 3D — the
## camera stays a Camera2D and the locked register is Don't-Starve / Stardew.
##
## Squash math: zoom = (default_zoom, default_zoom * (1 - tilt_amount)).
## tilt_amount = 0.0 → pure top-down flat. tilt_amount = 0.5 → heavy 45°-
## feeling squash. Default 0.15 reads as ~35° down without distorting
## sprite identity.
##
## Soft follow + lookahead: the camera is parented to the player. Godot's
## built-in position_smoothing handles the trail; this script controls the
## camera's local offset (lookahead) by reading parent velocity each frame.
## Lookahead is clamped so the player is never closer than min_screen_edge_margin
## to the screen edge.

@export_range(0.0, 0.5, 0.01) var tilt_amount: float = 0.15
## Zoom level on the X axis. Y is squashed by tilt_amount. ~2.0 fits ~12-16
## tiles vertically on a 720-1080p viewport.
@export var default_zoom: float = 2.0
## Pixels of camera lookahead applied in the player's movement direction.
## ~32-48 px (one iso tile) reads as a clear "the camera anticipates."
@export var lookahead_distance: float = 40.0
## How fast the lookahead offset eases in/out as the player turns. Higher
## = snappier; lower = smoother but laggier into direction changes.
@export var lookahead_smoothing: float = 4.0
## Minimum margin (as fraction of viewport size) the target must keep from
## the screen edge. 0.30 = target stays in the inner 40% of the viewport.
@export_range(0.0, 0.49, 0.01) var min_screen_edge_margin: float = 0.30
## Speed velocity must exceed before lookahead engages. Below this we
## treat the player as stationary (avoids jitter from sub-pixel drift).
@export var velocity_deadzone: float = 4.0

var _last_parent_pos: Vector2 = Vector2.ZERO
var _smoothed_lookahead: Vector2 = Vector2.ZERO
var _initialized: bool = false

func _ready() -> void:
	_apply_zoom()
	var parent_node: Node2D = _get_parent_node2d()
	if parent_node != null:
		_last_parent_pos = parent_node.global_position
	_initialized = true

func _apply_zoom() -> void:
	# Vertical squash creates the tilt-feel without rotating anything.
	# X stays at default; Y compresses by (1 - tilt_amount).
	zoom = Vector2(default_zoom, default_zoom * (1.0 - tilt_amount))

## Re-applies the zoom from current tilt_amount. Call after editing tilt_amount
## at runtime (debug overlay, settings change) so the squash updates without
## requiring a scene reload.
func refresh_tilt() -> void:
	_apply_zoom()

func _process(delta: float) -> void:
	if not _initialized:
		return
	var parent_node: Node2D = _get_parent_node2d()
	if parent_node == null:
		return
	var parent_pos: Vector2 = parent_node.global_position
	var dt: float = max(delta, 0.0001)
	var velocity: Vector2 = (parent_pos - _last_parent_pos) / dt
	_last_parent_pos = parent_pos

	var target_lookahead: Vector2 = Vector2.ZERO
	if velocity.length() > velocity_deadzone:
		target_lookahead = velocity.normalized() * lookahead_distance

	# Clamp by screen-edge margin. Viewport in world units = viewport_px / zoom.
	var viewport_world: Vector2 = get_viewport_rect().size / zoom
	var max_offset := Vector2(
		viewport_world.x * (0.5 - min_screen_edge_margin),
		viewport_world.y * (0.5 - min_screen_edge_margin),
	)
	target_lookahead.x = clamp(target_lookahead.x, -max_offset.x, max_offset.x)
	target_lookahead.y = clamp(target_lookahead.y, -max_offset.y, max_offset.y)

	# Smooth the lookahead transition itself so direction flips ease in.
	# 1 - exp(-k*dt) is a frame-rate-independent lerp factor.
	var t: float = 1.0 - exp(-lookahead_smoothing * dt)
	_smoothed_lookahead = _smoothed_lookahead.lerp(target_lookahead, t)
	# Local position because the camera is a child of the player. Godot's
	# built-in position_smoothing handles the global trail; we just set
	# the offset relative to the player.
	position = _smoothed_lookahead

func _get_parent_node2d() -> Node2D:
	var p: Node = get_parent()
	if p is Node2D:
		return p as Node2D
	return null
