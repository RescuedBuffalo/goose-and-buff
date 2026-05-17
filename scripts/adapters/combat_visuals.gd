extends Node2D
##
## Combat visuals — draws the swing arc when CombatSystem fires the
## swing_started signal, plus floating damage numbers when damage_dealt
## fires. No game logic here; this is purely the visible feedback layer.
##
## Lives as a sibling of the hero so swing arcs render in world space
## and y-sort with the rest of the entities.

const TILE_STEP_PX := 35.0

# Swing arc fade duration. Short — the arc reads as a flash, not a wipe.
const SWING_FLASH_SECONDS := 0.18

func attach(combat: CombatSystem) -> void:
	combat.swing_started.connect(_on_swing_started)
	combat.damage_dealt.connect(_on_damage_dealt)

func _on_swing_started(_weapon_id: String, origin: Vector2, dir: Vector2, length_px: float, half_angle_rad: float) -> void:
	var arc := Polygon2D.new()
	arc.color = Color(DesignTokens.PARCHMENT_0.r, DesignTokens.PARCHMENT_0.g, DesignTokens.PARCHMENT_0.b, 0.45)
	arc.position = origin
	arc.z_index = RenderLayers.WORLD_VFX
	# Build the cone polygon from a fan of points around the facing dir.
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var step: float = half_angle_rad / 4.0
	for i in range(-4, 5):
		var theta: float = float(i) * step
		var v: Vector2 = dir.rotated(theta) * length_px
		pts.append(v)
	arc.polygon = pts
	add_child(arc)
	var t := create_tween()
	t.tween_property(arc, "modulate:a", 0.0, SWING_FLASH_SECONDS)
	t.tween_callback(arc.queue_free)

func _on_damage_dealt(target_ref, amount: float) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	# Quick floating number — climbs and fades in ~0.6s.
	var label := Label.new()
	label.text = str(int(amount))
	label.modulate = DesignTokens.HP_CRIT
	label.add_theme_font_size_override("font_size", DesignTokens.FS_MD)
	label.position = (target_ref as Node2D).position + Vector2(-8, -36)
	label.z_index = RenderLayers.WORLD_LABELS
	add_child(label)
	var t := create_tween()
	t.parallel().tween_property(label, "position:y", label.position.y - 22.0, 0.6)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	t.tween_callback(label.queue_free)
