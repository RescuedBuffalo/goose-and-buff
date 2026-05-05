extends Control
##
## Letterboxed totem image. A `TextureRect` with `STRETCH_KEEP_ASPECT_CENTERED`
## would do this, but we want graceful fallback to a letter glyph when the
## texture is missing (Val until the SVG is wired in, neutral cards, etc.) and
## tinting per faction. Owns a single faction string; redraws on change.

var _faction: String = ""

func set_faction(faction: String) -> void:
	if faction == _faction:
		return
	_faction = faction
	queue_redraw()

func _draw() -> void:
	var tex: Texture2D = DesignTokens.totem_texture(_faction)
	var rect := Rect2(Vector2.ZERO, size)
	if tex != null:
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return
		var fit: float = min(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
		var draw_size := tex_size * fit
		var draw_pos := rect.position + (rect.size - draw_size) * 0.5
		draw_texture_rect(tex, Rect2(draw_pos, draw_size), false, Color.WHITE)
	else:
		# Missing-texture fallback — a single ink-tinted letter glyph.
		var glyph := "" if _faction.is_empty() else _faction.substr(0, 1)
		if glyph == "":
			return
		var font := DesignTokens.font_display()
		var fs := int(min(rect.size.x, rect.size.y) * 0.7)
		var text_w: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := rect.position + Vector2((rect.size.x - text_w) * 0.5, rect.size.y * 0.5 + fs * 0.35)
		draw_string(font, pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			DesignTokens.ink_color(_faction))
