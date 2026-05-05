extends Control
##
## Bottom-left ability rail. Shows the local hero's signature ability bound
## to Q with its keybind chip and a cooldown countdown. The 4-slot design
## (Q/E/F/R) from `design/ui_kits/hud/AbilityRail.jsx` collapses to a single
## Q slot in v0 — only the signature is wired.
##
## Listens to GameState.signature_cooldown_changed for the live cooldown
## value and rebuilds when the hero changes via set_hero().

const Heroes := preload("res://data/heroes.gd")

const SAFE_INSET := 24.0
const SLOT_SIZE := Vector2(56, 56)
const KEY_CHIP_SIZE := Vector2(20, 20)

var _hero_id: String = "Buffalo"
var _cooldown: float = 0.0
var _cooldown_max: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.signature_cooldown_changed.connect(_on_cooldown_changed)
	queue_redraw()

func set_hero(hero_id: String) -> void:
	_hero_id = hero_id
	queue_redraw()

func _on_cooldown_changed(remaining: float, maximum: float) -> void:
	_cooldown = remaining
	_cooldown_max = maximum
	queue_redraw()

func _draw() -> void:
	var origin := Vector2(SAFE_INSET, size.y - SAFE_INSET - SLOT_SIZE.y)
	var slot_rect := Rect2(origin, SLOT_SIZE)
	var on_cooldown: bool = _cooldown > 0.0
	# Slot background — dim when on cooldown so the state reads at a glance.
	var bg := Color(DesignTokens.NIGHT_1.r, DesignTokens.NIGHT_1.g, DesignTokens.NIGHT_1.b, 0.92)
	if on_cooldown:
		bg = Color(DesignTokens.NIGHT_2.r, DesignTokens.NIGHT_2.g, DesignTokens.NIGHT_2.b, 0.78)
	draw_rect(slot_rect, bg, true)
	# Hi-fi v3 border rule: 1px hero-core at 0.45 alpha — same on the slot
	# and the keybind chip so the rail reads as one component.
	var border := DesignTokens.hero_core_border(_hero_id)
	draw_rect(slot_rect, border, false, 1.0)
	# Keybind chip (top-left of the slot, slightly outside).
	var chip_rect := Rect2(origin + Vector2(-6, -6), KEY_CHIP_SIZE)
	draw_rect(chip_rect, DesignTokens.NIGHT_2, true)
	draw_rect(chip_rect, border, false, 1.0)
	_draw_centered("Q", chip_rect, DesignTokens.FG_2, DesignTokens.FS_XS)
	# Slot interior — number while on cooldown, totem letter otherwise.
	var accent := DesignTokens.core_color(_hero_id)
	if on_cooldown:
		var label := str(int(ceil(_cooldown)))
		_draw_centered(label, slot_rect, DesignTokens.FG_1, DesignTokens.FS_XL)
	else:
		var glyph := _hero_glyph(_hero_id)
		_draw_centered(glyph, slot_rect, accent, DesignTokens.FS_2XL)
	# Bottom progress bar — empty -> full as the cooldown drains.
	if on_cooldown and _cooldown_max > 0.0:
		var bar_h := 3.0
		var ratio := 1.0 - (_cooldown / _cooldown_max)
		draw_rect(Rect2(origin.x, origin.y + SLOT_SIZE.y - bar_h, SLOT_SIZE.x, bar_h),
			DesignTokens.NIGHT_3, true)
		draw_rect(Rect2(origin.x, origin.y + SLOT_SIZE.y - bar_h, SLOT_SIZE.x * ratio, bar_h),
			Color(accent.r, accent.g, accent.b, 0.85), true)
	# Ability name caption to the right of the slot — helps newcomers learn
	# which signature their hero is on. Uses the in-full hero name per voice.
	var hero_def: Dictionary = Heroes.ALL.get(_hero_id, Heroes.Buffalo)
	var caption: String = String(hero_def.get("signatureAbility", ""))
	if caption != "":
		var caption_pos := Vector2(origin.x + SLOT_SIZE.x + 12.0, origin.y + SLOT_SIZE.y * 0.5 - 8.0)
		_draw_label(caption, caption_pos, DesignTokens.FG_3, DesignTokens.FS_SM)

func _hero_glyph(hero_id: String) -> String:
	# v0 placeholder — first letter of the hero's name. M3 swaps in the
	# Lucide-styled ability glyphs called out in AbilityRail.jsx.
	if hero_id.is_empty():
		return ""
	return hero_id.substr(0, 1)

func _draw_centered(text: String, rect: Rect2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := rect.position + Vector2((rect.size.x - w) * 0.5, rect.size.y * 0.5 + font_size * 0.35)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
