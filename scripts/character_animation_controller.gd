class_name CharacterAnimationController
extends Node
##
## State machine for the 7-state character animation set (BUF-183):
##
##   IDLE       — subtle chest breathing, head bob, occasional half-blinks
##   WALK       — leg cycle + arm swing + slight torso bob
##   ATTACK     — wind-up → swing → recover
##   GATHER     — overhead → swing-down → impact → return loop
##   HIT_REACT  — backward recoil, head tilt, settle to idle
##   DEATH      — knees buckle → drop → tip forward, holds final frame
##   BLINK      — eye-state cycle (open → half → closed → half → open)
##
## ─── Idle blink ───────────────────────────────────────────────────────────
##
## BLINK is special: it only plays on top of IDLE, on a random 2.5–4s
## cadence, and returns to IDLE when finished. The state transition is
## driven from this controller's _process tick — Hero/Enemy adapter doesn't
## need to know about blink.
##
## ─── Other transitions ────────────────────────────────────────────────────
##
## Hero/Enemy adapter calls `transition_to(state)` based on gameplay:
##   - Movement vector zero  → IDLE
##   - Movement vector nonzero → WALK
##   - Click input            → ATTACK (transitions back to IDLE/WALK on finish)
##   - Gather interaction     → GATHER (looped during gather hold)
##   - Damage taken           → HIT_REACT
##   - HP <= 0                → DEATH (terminal — no further transitions)
##
## ATTACK / HIT_REACT auto-return to IDLE/WALK when the AnimationPlayer's
## animation_finished signal fires for them. Per-character scenes can override
## the animation name strings via set_animation_name() if they use different
## conventions (e.g. Wolf uses "lunge" instead of "attack").

enum State { IDLE, WALK, ATTACK, GATHER, HIT_REACT, DEATH, BLINK }

# State → animation_name mapping. Per-character overrides via
# set_animation_name() for renamed animations (Wolf "lunge", Owl "swoop",
# enemies' "frost_shatter_death", etc.).
var _animation_names: Dictionary = {
	State.IDLE: "idle",
	State.WALK: "walk",
	State.ATTACK: "attack",
	State.GATHER: "gather",
	State.HIT_REACT: "hit_react",
	State.DEATH: "death",
	State.BLINK: "blink",
}

# Idle blink cadence — a fresh delay sampled in this range every time
# blink finishes. Avoids the mechanical "blinks exactly every 3.0s"
# tell that breaks the illusion.
const BLINK_MIN_INTERVAL := 2.5
const BLINK_MAX_INTERVAL := 4.0

# AnimationPlayer to drive. Resolved in _ready: prefer the explicit path
# if set, otherwise auto-find a sibling AnimationPlayer.
@export var animation_player_path: NodePath

var anim: AnimationPlayer = null
var current_state: int = State.IDLE
var _blink_timer: float = 0.0
# True while a non-loopable transient animation (ATTACK / HIT_REACT) is
# playing. While true, _process won't trigger blinks even if the underlying
# state is IDLE.
var _transient_playing: bool = false

func _ready() -> void:
	anim = _resolve_animation_player()
	if anim == null:
		push_warning("[anim %s] no AnimationPlayer found; controller is inert" % name)
		return
	anim.animation_finished.connect(_on_animation_finished)
	_schedule_next_blink()
	_play_state(State.IDLE)

func _resolve_animation_player() -> AnimationPlayer:
	if animation_player_path != NodePath(""):
		var node := get_node_or_null(animation_player_path)
		if node is AnimationPlayer:
			return node
	# Fallback: sibling AnimationPlayer alongside this controller (the rig
	# templates place an AnimationPlayer at the rig root, sibling to this
	# controller).
	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("AnimationPlayer")
		if sibling is AnimationPlayer:
			return sibling
	return null

## Move to a new logical state. No-op if already in that state (except
## DEATH, which is terminal and ignored once entered).
func transition_to(new_state: int) -> void:
	if current_state == State.DEATH:
		return
	if new_state == current_state:
		return
	current_state = new_state
	_play_state(new_state)

## Per-character override for an animation name. Lets Wolf ship with
## "lunge" / "frost_shatter_death" while sharing this controller.
func set_animation_name(state: int, anim_name: String) -> void:
	_animation_names[state] = anim_name

func _play_state(state: int) -> void:
	if anim == null:
		return
	var anim_name: String = _animation_names.get(state, "")
	if anim_name == "" or not anim.has_animation(anim_name):
		return
	# ATTACK and HIT_REACT are transient — flag them so blink scheduling
	# pauses until they're done (signaled via animation_finished).
	_transient_playing = (state == State.ATTACK or state == State.HIT_REACT)
	anim.play(anim_name)

func _process(delta: float) -> void:
	if anim == null:
		return
	# Blink only fires on top of a quiet IDLE (not WALK, not transients).
	if current_state != State.IDLE or _transient_playing:
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_trigger_blink()
		_schedule_next_blink()

func _trigger_blink() -> void:
	if anim == null:
		return
	var blink_name: String = _animation_names.get(State.BLINK, "blink")
	if anim.has_animation(blink_name):
		anim.play(blink_name)
		# State stays IDLE; blink is a one-shot overlay. animation_finished
		# below restores the IDLE animation when blink ends.

func _schedule_next_blink() -> void:
	_blink_timer = randf_range(BLINK_MIN_INTERVAL, BLINK_MAX_INTERVAL)

func _on_animation_finished(finished_name: String) -> void:
	# Transient animations return to the underlying state when done.
	# Blink is a special-case overlay that always returns to IDLE.
	var blink_name: String = _animation_names.get(State.BLINK, "blink")
	if finished_name == blink_name:
		_play_state(State.IDLE)
		return
	if _transient_playing:
		_transient_playing = false
		# After ATTACK / HIT_REACT, fall back to IDLE — Hero/Enemy
		# adapter can immediately call transition_to(WALK) again next tick
		# if movement is still active.
		if current_state == State.ATTACK or current_state == State.HIT_REACT:
			current_state = State.IDLE
			_play_state(State.IDLE)
