extends Node2D
##
## Draws the Buffalo sector: floor, spawn pad, core. Owns the core HP
## state and emits when it changes.

const Sectors := preload("res://data/sectors.gd")

signal core_hp_changed(current: float, maximum: float)
signal core_destroyed()

var core_hp: float = Sectors.CORE_HEALTH
var core_hp_max: float = Sectors.CORE_HEALTH

func _ready() -> void:
	add_to_group("sector")
	GameState.core_hp = core_hp
	GameState.core_hp_max = core_hp_max
	queue_redraw()

func damage_core(amount: float) -> void:
	core_hp = max(0.0, core_hp - amount)
	GameState.core_hp = core_hp
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()
	if core_hp <= 0.0:
		core_destroyed.emit()

func reset_core() -> void:
	core_hp = core_hp_max
	GameState.core_hp = core_hp
	core_hp_changed.emit(core_hp, core_hp_max)
	queue_redraw()

func _draw() -> void:
	# Floor.
	var floor_rect := Rect2(
		Vector2(Sectors.SECTOR_LEFT, Sectors.SECTOR_TOP),
		Vector2(Sectors.SECTOR_RIGHT - Sectors.SECTOR_LEFT,
			Sectors.SECTOR_BOTTOM - Sectors.SECTOR_TOP),
	)
	draw_rect(floor_rect, DesignTokens.BUFFALO_FLOOR, true)
	# Spawn pad.
	var pad_rect := Rect2(
		Sectors.SPAWN_PAD_CENTER - Sectors.SPAWN_PAD_SIZE * 0.5,
		Sectors.SPAWN_PAD_SIZE,
	)
	draw_rect(pad_rect, DesignTokens.PARCHMENT_2, true)
	draw_rect(pad_rect, DesignTokens.BUFFALO_INK, false, 2.0)
	# Core.
	var core_rect := Rect2(
		Sectors.CORE_CENTER - Sectors.CORE_SIZE * 0.5,
		Sectors.CORE_SIZE,
	)
	draw_rect(core_rect, DesignTokens.BUFFALO_CORE, true)
	draw_rect(core_rect, DesignTokens.NIGHT_0, false, 2.0)
	# Core HP arc — a thin bar above the core.
	var bar_y := Sectors.CORE_CENTER.y - Sectors.CORE_SIZE.y * 0.5 - 12.0
	var bar_w := Sectors.CORE_SIZE.x + 16.0
	var bar_x := Sectors.CORE_CENTER.x - bar_w * 0.5
	var hp_ratio: float = 0.0 if core_hp_max == 0 else core_hp / core_hp_max
	draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), DesignTokens.NIGHT_3, true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, 4.0), DesignTokens.hp_color(hp_ratio), true)
	# Hand divider — a thin line where the playable area ends.
	draw_line(
		Vector2(Sectors.SECTOR_LEFT, Sectors.SECTOR_BOTTOM),
		Vector2(Sectors.SECTOR_RIGHT, Sectors.SECTOR_BOTTOM),
		DesignTokens.DIVIDER, 2.0,
	)
