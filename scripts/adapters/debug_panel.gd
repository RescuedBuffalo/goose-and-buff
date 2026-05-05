extends Control
##
## Debug stats panel (BUF-145) — sibling of debug_overlay but anchored
## in screen space inside the HUD canvas layer. Shows the current seed,
## day_index, and climate distribution counts at the top-left corner.
## Toggled in lock-step with the world-space overlay.

const WorldGenerator := preload("res://scripts/logic/world_generator.gd")

var visible_overlay: bool = false
var world_def: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor: top-left corner. Width fixed so wrapping is predictable.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 16
	offset_top = 110     # below the top HUD band (96 px tall + gap)
	offset_right = 296
	offset_bottom = 240

func set_world(def: Dictionary) -> void:
	world_def = def
	queue_redraw()

func toggle() -> void:
	visible_overlay = not visible_overlay
	queue_redraw()

func _draw() -> void:
	if not visible_overlay or world_def.is_empty():
		return
	var bg := Color(DesignTokens.NIGHT_0.r, DesignTokens.NIGHT_0.g, DesignTokens.NIGHT_0.b, 0.78)
	draw_rect(Rect2(0, 0, size.x, size.y), bg, true)
	draw_rect(Rect2(0, 0, size.x, size.y), DesignTokens.PARCHMENT_2, false, 1.0)
	var font: Font = ThemeDB.fallback_font
	var pad: float = 12.0
	var y: float = 22.0
	var lh: float = 18.0
	draw_string(font, Vector2(pad, y), "DEBUG — F3 to hide",
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_XS, DesignTokens.FG_3)
	y += lh
	var seed_int: int = int(world_def.get("seed", 0))
	draw_string(font, Vector2(pad, y), "Seed " + WorldGenerator.seed_to_string(seed_int),
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.PARCHMENT_0)
	y += lh
	draw_string(font, Vector2(pad, y), "Day index %d" % int(world_def.get("day_index", 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.PARCHMENT_0)
	y += lh
	var stats: Dictionary = world_def.get("stats", {})
	var dist: Dictionary = stats.get("climate_distribution", {})
	for k in ["temperate", "frosted", "frozen", "any"]:
		if int(dist.get(k, 0)) <= 0 and k != "temperate":
			continue
		draw_string(font, Vector2(pad, y),
				"%s %d" % [k, int(dist.get(k, 0))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_2)
		y += lh
	draw_string(font, Vector2(pad, y),
			"Resources %d" % int(stats.get("resource_count", 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FS_SM, DesignTokens.FG_2)
