class_name CharacterShadow
extends Node2D
##
## Soft elliptical shadow drawn at the character's feet (BUF-181). Sits as
## a child of the player root before the Sprite2D so it draws underneath.
## Asset canon is cream-isolated (no baked shadow), so every character
## ground-shadow is rendered procedurally here for consistency.

@export var radius_x: float = 18.0
@export var radius_y: float = 6.0
@export var alpha: float = 0.35
@export var color_rgb: Color = Color(0, 0, 0)
## Number of segments around the ellipse. 24 reads smooth at typical zoom
## without burning fill rate on a non-feature element.
@export_range(8, 64, 2) var segments: int = 24

func _draw() -> void:
	if radius_x <= 0.0 or radius_y <= 0.0 or alpha <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(theta) * radius_x, sin(theta) * radius_y))
	var col := Color(color_rgb.r, color_rgb.g, color_rgb.b, alpha)
	var colors := PackedColorArray()
	for _i in range(segments):
		colors.append(col)
	draw_polygon(pts, colors)
