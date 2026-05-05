extends Node2D
##
## Draws the playable sector: floor, spawn pad, core. Owns the core HP
## state and emits when it changes.
##
## Sector geometry is shared (`data/sectors.gd`); palette is driven by
## the selected hero so picking Goose / Buffalo / Fox visibly retones the
## arena. Multi-sector layouts (one per hero, side-by-side) are an M4
## multiplayer concern — for solo we recolor the single sector.

const Sectors := preload("res://data/sectors.gd")

signal core_hp_changed(current: float, maximum: float)
signal core_destroyed()

var core_hp: float = Sectors.CORE_HEALTH
var core_hp_max: float = Sectors.CORE_HEALTH
var hero_id: String = "Buffalo"
# Lit while the player is dragging a unit / building card. Visualizes the
# legal drop area so cards don't feel point-imprecise (BUF-110).
var _deploy_highlight: bool = false

func _ready() -> void:
	add_to_group("sector")
	GameState.core_hp = core_hp
	GameState.core_hp_max = core_hp_max
	queue_redraw()

func set_hero(new_hero_id: String) -> void:
	# Repaint with the new faction palette. Called by main.gd after the
	# player locks in on the hero select screen.
	hero_id = new_hero_id
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

func set_deploy_highlight(active: bool) -> void:
	if _deploy_highlight == active:
		return
	_deploy_highlight = active
	queue_redraw()

func _draw() -> void:
	var floor_color := DesignTokens.floor_color(hero_id)
	var core_color := DesignTokens.core_color(hero_id)
	var ink_color := DesignTokens.ink_color(hero_id)
	# Floor.
	var floor_rect := Rect2(
		Vector2(Sectors.SECTOR_LEFT, Sectors.SECTOR_TOP),
		Vector2(Sectors.SECTOR_RIGHT - Sectors.SECTOR_LEFT,
			Sectors.SECTOR_BOTTOM - Sectors.SECTOR_TOP),
	)
	draw_rect(floor_rect, floor_color, true)
	# Spawn pad.
	var pad_rect := Rect2(
		Sectors.SPAWN_PAD_CENTER - Sectors.SPAWN_PAD_SIZE * 0.5,
		Sectors.SPAWN_PAD_SIZE,
	)
	draw_rect(pad_rect, DesignTokens.PARCHMENT_2, true)
	draw_rect(pad_rect, ink_color, false, 2.0)
	# Core.
	var core_rect := Rect2(
		Sectors.CORE_CENTER - Sectors.CORE_SIZE * 0.5,
		Sectors.CORE_SIZE,
	)
	draw_rect(core_rect, core_color, true)
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
	# Deploy zone overlay — only visible while a unit/building card is being
	# dragged. Tinted with the hero's accent color so the boundary reads at a
	# glance without overwhelming the floor underneath.
	if _deploy_highlight:
		var accent := DesignTokens.core_color(hero_id)
		var tint := Color(accent.r, accent.g, accent.b, 0.18)
		draw_rect(floor_rect, tint, true)
		var border := Color(accent.r, accent.g, accent.b, 0.85)
		draw_rect(floor_rect, border, false, 4.0)
