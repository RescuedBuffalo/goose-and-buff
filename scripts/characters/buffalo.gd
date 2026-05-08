extends CharacterRigController
class_name BuffaloRig
##
## Buffalo character rig (BUF-183 Phase 3).
##
## Inherits from CharacterRigController and populates each Sprite2D slot
## from buffalo_rigging_sheet.png via AtlasTextures sliced from
## BuffaloRigParts.
##
## Buffalo's rig follows the bipedal template's bone hierarchy but uses
## simplified arm + leg part counts:
##   - Arms are 2-segment (upper_arm sleeve + hand) — the forearm bone in
##     the template still exists for animation purposes but its sprite
##     slot stays empty (the sleeve covers what the forearm bone moves).
##   - Legs are 2-segment (thigh + calf-with-hoof-baked) — same deal,
##     the foot bone still exists for animation but the calf sprite has
##     the hoof painted in already.
##
## Front-facing only for Phase 3. Direction sprite-swap to LEFT/RIGHT
## falls back to FRONT with horizontal flip via the controller's logic.
## BACK direction generates a one-time warning until a back-facing parts
## sheet is authored.

const Parts := preload("res://data/buffalo_rig_parts.gd")
# Direction is inherited from CharacterRigController — no need to redeclare.

# Sprite anchor enum — where on the part texture the bone's pivot lands.
# TOP   = bone pivot at top edge of texture (shoulders, hips: limbs hang from it)
# BOTTOM = bone pivot at bottom edge (head: neck attaches at the bottom)
# CENTER = bone pivot at texture center (tail, decorative parts)
enum Anchor { TOP, BOTTOM, CENTER }

# Per-part rendering setup: which atlas region to use, the sprite scale
# (atlases come in at sheet resolution ~100-200px; we scale down ~0.1
# to match the bone positions that target a ~50px character), and where
# the bone pivot anchors on the texture.
const _PART_SETUP: Dictionary = {
	"head":         { "rect": Parts.HEAD_NEUTRAL, "scale": 0.10, "anchor": Anchor.BOTTOM },
	"torso":        { "rect": Parts.JACKET,       "scale": 0.10, "anchor": Anchor.TOP },
	"upper_arm_l":  { "rect": Parts.UPPER_ARM_L,  "scale": 0.10, "anchor": Anchor.TOP },
	"upper_arm_r":  { "rect": Parts.UPPER_ARM_R,  "scale": 0.10, "anchor": Anchor.TOP },
	"hand_l":       { "rect": Parts.HAND_POSE_A,  "scale": 0.10, "anchor": Anchor.TOP },
	"hand_r":       { "rect": Parts.HAND_POSE_A,  "scale": 0.10, "anchor": Anchor.TOP },
	"thigh_l":      { "rect": Parts.THIGH,        "scale": 0.10, "anchor": Anchor.TOP },
	"thigh_r":      { "rect": Parts.THIGH,        "scale": 0.10, "anchor": Anchor.TOP },
	"calf_l":       { "rect": Parts.CALF_HOOF,    "scale": 0.10, "anchor": Anchor.TOP },
	"calf_r":       { "rect": Parts.CALF_HOOF,    "scale": 0.10, "anchor": Anchor.TOP },
	"tail":         { "rect": Parts.TAIL,         "scale": 0.10, "anchor": Anchor.CENTER },
}

# Cached source — Texture2D for the rigging sheet. AtlasTextures share
# this single base texture, so the GPU only uploads the sheet once.
var _sheet: Texture2D = null

func _ready() -> void:
	super._ready()
	_sheet = load(Parts.SHEET_PATH)
	if _sheet == null:
		push_warning("[buffalo] could not load rigging sheet at ", Parts.SHEET_PATH)
		return
	_register_parts()
	_assign_atlases()
	# Default to FRONT facing on spawn.
	set_direction(Direction.FRONT)

func _register_parts() -> void:
	# Map logical part names → Sprite2D slot in the bipedal template. The
	# names are what the controller's set_direction() iterates over to
	# decide which sprites get atlas-swapped on direction change.
	register_part("torso", get_node_or_null("Skeleton2D/root/spine/TorsoSprite") as Sprite2D)
	register_part("head", get_node_or_null("Skeleton2D/root/spine/head/HeadSprite") as Sprite2D)
	register_part("upper_arm_l", get_node_or_null("Skeleton2D/root/spine/shoulder_l/upper_arm_l/UpperArmLSprite") as Sprite2D)
	register_part("upper_arm_r", get_node_or_null("Skeleton2D/root/spine/shoulder_r/upper_arm_r/UpperArmRSprite") as Sprite2D)
	register_part("hand_l", get_node_or_null("Skeleton2D/root/spine/shoulder_l/upper_arm_l/forearm_l/hand_l/HandLSprite") as Sprite2D)
	register_part("hand_r", get_node_or_null("Skeleton2D/root/spine/shoulder_r/upper_arm_r/forearm_r/hand_r/HandRSprite") as Sprite2D)
	register_part("thigh_l", get_node_or_null("Skeleton2D/root/hip_l/thigh_l/ThighLSprite") as Sprite2D)
	register_part("thigh_r", get_node_or_null("Skeleton2D/root/hip_r/thigh_r/ThighRSprite") as Sprite2D)
	register_part("calf_l", get_node_or_null("Skeleton2D/root/hip_l/thigh_l/calf_l/CalfLSprite") as Sprite2D)
	register_part("calf_r", get_node_or_null("Skeleton2D/root/hip_r/thigh_r/calf_r/CalfRSprite") as Sprite2D)
	register_part("tail", get_node_or_null("Skeleton2D/root/tail/TailSprite") as Sprite2D)

func _assign_atlases() -> void:
	# FRONT-only for Phase 3. Each entry is a single-direction dict; the
	# controller's set_direction() falls back to FRONT-with-flip for L/R
	# and FRONT-with-warning for BACK.
	for part_name in _PART_SETUP.keys():
		var setup: Dictionary = _PART_SETUP[part_name]
		var atlas: AtlasTexture = _atlas(setup.rect)
		set_part_atlases(part_name, { Direction.FRONT: atlas })
		# Sprite-level scale + offset — the bone hierarchy targets a ~50px
		# character but our atlas regions are at sheet resolution (~100-
		# 200px), so each sprite scales down to match. Anchor places the
		# bone's pivot at the appropriate point on the texture.
		var sprite: Sprite2D = part_sprites.get(part_name)
		if sprite == null:
			continue
		sprite.scale = Vector2(setup.scale, setup.scale)
		sprite.offset = _anchor_offset(setup.anchor, setup.rect.size)

func _anchor_offset(anchor: int, size: Vector2i) -> Vector2:
	# offset is in PRE-scale texture pixels for centered=true sprites.
	# Sprite renders the texture from (-w/2, -h/2 + offset.y) to
	# (+w/2, +h/2 + offset.y) in local space.
	match anchor:
		Anchor.TOP:
			return Vector2(0, float(size.y) * 0.5)
		Anchor.BOTTOM:
			return Vector2(0, -float(size.y) * 0.5)
		_:
			return Vector2.ZERO

func _atlas(region: Rect2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet
	atlas.region = Rect2(region)
	return atlas
