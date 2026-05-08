extends CharacterRigController
class_name BuffaloRig
##
## Buffalo character rig (BUF-183 Phase 3).
##
## All texture assignments + scale + offset live directly in
## scenes/characters/buffalo.tscn so the rig is fully editable in the
## Godot editor: open buffalo.tscn, click any Bone2D, drag to reposition,
## save. The parts follow the bones live.
##
## This script's only Phase 3 job is to register each Sprite2D slot with
## the inherited CharacterRigController so future direction-swap calls
## (Phase 4 BACK/LEFT/RIGHT atlases) know which sprite holds which logical
## part. set_part_atlases is NOT called here — the texture assigned in
## the .tscn IS the FRONT-direction art, so set_direction(FRONT) is a
## no-op.

func _ready() -> void:
	super._ready()
	_register_parts()
	current_direction = Direction.FRONT

func _register_parts() -> void:
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
