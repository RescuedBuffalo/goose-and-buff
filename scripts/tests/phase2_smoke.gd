extends SceneTree
##
## Phase 2 BUF-183 smoke test. Run via:
##   godot --headless --script res://scripts/tests/phase2_smoke.gd
## Confirms the rig templates load + instantiate cleanly and the
## CharacterDirection helper maps velocities correctly.
##
## Note: --script doesn't load the project's class_name registry, so
## class_name'd identifiers (CharacterDirection, etc.) aren't resolved
## as global names here. We preload the script directly instead.

const _CharacterDirection := preload("res://scripts/character_direction.gd")

func _initialize() -> void:
	print("\n=== Phase 2 BUF-183 smoke test ===\n")
	for path in [
		"res://scenes/characters/character_rig_bipedal.tscn",
		"res://scenes/characters/character_rig_quadruped.tscn",
	]:
		var packed: PackedScene = load(path)
		if packed == null:
			print("  FAIL: ", path, " did not load")
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			print("  FAIL: ", path, " did not instantiate")
			continue
		var counts := _count(inst)
		print("  ", path)
		print("    bones=", counts.bones, ", sprite slots=", counts.sprites,
			", anim_player=", counts.anim_player, ", rig_ctrl=", counts.rig_ctrl,
			", anim_ctrl=", counts.anim_ctrl)
		inst.queue_free()

	print("\n  _CharacterDirection.from_velocity:")
	print("    (1,  0) → ", _CharacterDirection.name_for(_CharacterDirection.from_velocity(Vector2(1, 0))))
	print("    (-1, 0) → ", _CharacterDirection.name_for(_CharacterDirection.from_velocity(Vector2(-1, 0))))
	print("    (0,  1) → ", _CharacterDirection.name_for(_CharacterDirection.from_velocity(Vector2(0, 1))))
	print("    (0, -1) → ", _CharacterDirection.name_for(_CharacterDirection.from_velocity(Vector2(0, -1))))
	print("    (.7,.7) → ", _CharacterDirection.name_for(_CharacterDirection.from_velocity(Vector2(0.707, 0.707))))
	print("    (0,  0) → from_velocity returns ", _CharacterDirection.from_velocity(Vector2(0, 0)), " (expect -1)")
	print("\n=== smoke test complete ===\n")
	quit()

func _count(node: Node) -> Dictionary:
	var bones: int = 0
	var sprites: int = 0
	var anim_player: bool = false
	var rig_ctrl: bool = false
	var anim_ctrl: bool = false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Bone2D:
			bones += 1
		if n is Sprite2D:
			sprites += 1
		if n is AnimationPlayer:
			anim_player = true
		var script: Script = n.get_script()
		if script != null:
			var rp: String = script.resource_path
			if rp.ends_with("character_rig_controller.gd"):
				rig_ctrl = true
			elif rp.ends_with("character_animation_controller.gd"):
				anim_ctrl = true
		for c in n.get_children():
			stack.append(c)
	return {
		"bones": bones,
		"sprites": sprites,
		"anim_player": anim_player,
		"rig_ctrl": rig_ctrl,
		"anim_ctrl": anim_ctrl,
	}
