extends Node2D
##
## Boot script. Builds logic modules, instantiates scene-tree adapters,
## wires signals between them. The only place where the layers meet.
##
## The split mirrors the Roblox project: pure GDScript modules carry
## state and emit signals; adapters subscribe and translate to scene
## changes. The wiring stays in this single file.

const Sectors := preload("res://data/sectors.gd")
const Heroes := preload("res://data/heroes.gd")
const Cards := preload("res://data/cards.gd")
# Logic classes (Economy, CardSystem, WaveDirector, AbilityResolver) and the
# data classes that have a class_name are reachable as globals — no need to
# alias them via const here.

const SectorScene := preload("res://scenes/sector.tscn")
const HeroScene := preload("res://scenes/hero.tscn")
const UnitScene := preload("res://scenes/unit.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BuildingScene := preload("res://scenes/building.tscn")
const HandScene := preload("res://scenes/ui/hand.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const EndScene := preload("res://scenes/ui/end_screen.tscn")
const HeroSelectScene := preload("res://scenes/ui/hero_select.tscn")
const LodgeScene := preload("res://scenes/ui/lodge.tscn")
const AbilityRailScene := preload("res://scenes/ui/ability_rail.tscn")
const WaveCompPanelScene := preload("res://scenes/ui/wave_comp_panel.tscn")
const HelpBannerScene := preload("res://scenes/ui/help_banner.tscn")

# Logic
var economy
var card_system
var wave_director

# Adapters / scene refs
var sector
var hero
var hand
var hud
var end_screen
var hero_select
var lodge
var ability_rail
var wave_comp_panel
var help_banner
var building_node: Node = null  # at most one in v0
# Signature ability cooldown — counted down each frame in _process while a
# wave is live. Zero means "ready to cast".
var _signature_cd_remaining: float = 0.0
var _signature_cd_max: float = 0.0
# Aim ghost-line shown while an ability card is being dragged. Owned here
# (not by the hand widget) because it lives in the world layer alongside
# the hero, and only main has the hero reference. Null when no drag is
# active or the active drag is a non-ability card.
var _aim_line: Line2D = null
var _aim_target: Vector2 = Vector2.ZERO
var _aim_card_id: String = ""
# Hero is rebuilt fresh each run so a different pick can swap sprite +
# stats. Keeping it nullable lets _start_run handle both first launch
# (no hero yet) and post-restart (old hero already freed).

func _ready() -> void:
	randomize()
	_build_logic()
	_build_world()
	_build_ui()
	_wire_signals()
	_open_lodge()

func _build_logic() -> void:
	economy = Economy.new()
	card_system = CardSystem.new()
	wave_director = WaveDirector.new()

func _build_world() -> void:
	# The hero is intentionally NOT instanced here — _start_run instances it
	# fresh per pick so hero_data / sprite / spawn pad reflect the choice.
	sector = SectorScene.instantiate()
	add_child(sector)

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = HudScene.instantiate()
	ui_layer.add_child(hud)
	hand = HandScene.instantiate()
	ui_layer.add_child(hand)
	end_screen = EndScene.instantiate()
	ui_layer.add_child(end_screen)
	hero_select = HeroSelectScene.instantiate()
	ui_layer.add_child(hero_select)
	lodge = LodgeScene.instantiate()
	ui_layer.add_child(lodge)
	ability_rail = AbilityRailScene.instantiate()
	ui_layer.add_child(ability_rail)
	wave_comp_panel = WaveCompPanelScene.instantiate()
	ui_layer.add_child(wave_comp_panel)
	help_banner = HelpBannerScene.instantiate()
	ui_layer.add_child(help_banner)

func _wire_signals() -> void:
	hud.bind(economy, wave_director, sector)
	hand.bind(card_system, economy)
	hand.play_requested.connect(_on_play_requested)
	hand.drag_started.connect(_on_drag_started)
	hand.drag_moved.connect(_on_drag_moved)
	hand.drag_ended.connect(_on_drag_ended)
	card_system.card_played.connect(_on_card_played)
	wave_director.enemy_due.connect(_on_enemy_due)
	wave_director.run_complete.connect(_on_run_complete)
	wave_director.run_ended.connect(_on_run_ended)
	wave_director.round_started.connect(_on_round_started)
	wave_director.wave_started.connect(_on_wave_started)
	wave_director.wave_ended.connect(_on_wave_ended)
	sector.core_destroyed.connect(_on_core_destroyed)
	end_screen.restart_requested.connect(_on_restart_requested)
	end_screen.back_to_lodge_requested.connect(_on_back_to_lodge_requested)
	hero_select.hero_selected.connect(_on_hero_selected)
	lodge.pick_hero_requested.connect(_on_lodge_pick_hero_requested)
	lodge.start_run_requested.connect(_on_lodge_start_run_requested)
	lodge.unlock_cards_requested.connect(_on_lodge_unlock_cards_requested)

func _open_lodge() -> void:
	# The Lodge is the entry point and the post-run hub (BUF-112). Hide
	# every in-run surface so the room reads clean, and pause the wave
	# clock so the 30s prep timer doesn't tick behind the curtain (see
	# _process — it short-circuits while the lodge is up).
	GameState.set_phase(GameState.Phase.LODGE)
	end_screen.visible = false
	hero_select.close()
	hud.visible = false
	hand.visible = false
	if ability_rail != null:
		ability_rail.visible = false
	if wave_comp_panel != null:
		wave_comp_panel.hide_panel()
	if help_banner != null:
		help_banner.clear_help()
	lodge.open()

func _open_hero_select() -> void:
	# Reachable from the Lodge's "Pick your hero" station. We don't change
	# GameState's phase here — the player is mid-flow inside the Lodge
	# (Phase.LODGE still applies). On selection we route back to the lodge
	# with the new hero set; nothing starts the run from this path.
	if lodge != null:
		lodge.close()
	hero_select.open()

func _on_hero_selected(hero_id: String) -> void:
	GameState.set_hero(hero_id)
	# Sector retones immediately so when the run starts (from the Lodge's
	# "Start a run" station), the curtain pull-back lands on the correct
	# palette without an extra frame of stale color.
	sector.set_hero(hero_id)
	# Pick happened from inside the Lodge — return there so the player
	# can see the new hero reflected in the Start station before going.
	_open_lodge()

func _on_lodge_pick_hero_requested() -> void:
	_open_hero_select()

func _on_lodge_start_run_requested() -> void:
	# Leaving the Lodge for the dark — instantiate the hero, light up the
	# in-run UI, and hand the wave clock back to _process.
	lodge.close()
	sector.set_hero(GameState.hero_id)
	_spawn_hero(GameState.hero_id)
	hud.visible = true
	hand.visible = true
	ability_rail.visible = true
	ability_rail.set_hero(GameState.hero_id)
	if wave_comp_panel != null:
		wave_comp_panel.hide_panel()
	if help_banner != null:
		help_banner.clear_help()
	_start_run()

func _on_lodge_unlock_cards_requested() -> void:
	# v1 stub — the Lodge surfaces its own toast on click. Nothing to do
	# here yet; the signal exists so M2's card-unlocks work has a wire to
	# hook into without restructuring the Lodge.
	pass

func _spawn_hero(hero_id: String) -> void:
	# Tear down any prior hero defensively. _on_back_to_lodge_requested
	# already frees on the run-end path; this guard catches any future
	# entry that forgets.
	if hero != null and is_instance_valid(hero):
		hero.queue_free()
	hero = HeroScene.instantiate()
	hero.set_hero(hero_id)
	add_child(hero)
	hero.hero_downed.connect(_on_hero_downed)

func _start_run() -> void:
	GameState.reset()
	# Republish world-owned state into GameState — GameState.reset() zeroed
	# core/hero HP, and the sector/hero set their values during _ready, so
	# without this the HUD would show 0/0 until the first damage tick.
	sector.reset_core()
	hero.reset_hp()
	hero.reset_position()
	economy.reset()
	card_system.reset(GameState.hero_id)
	# wave_director.reset() emits round_started, which _on_round_started
	# routes back into card_system.start_round(); calling it again here
	# would double-fire hand_changed and rebuild the hand twice.
	wave_director.reset()
	GameState.set_phase(GameState.Phase.PREP)
	_reset_signature_cooldown()

func _process(delta: float) -> void:
	# Don't tick the run while the lodge or hero select is up — otherwise
	# the prep timer would burn down behind the curtain.
	if lodge != null and lodge.visible:
		return
	if hero_select != null and hero_select.visible:
		return
	# Drive logic ticks. WaveDirector + Economy progress only here.
	wave_director.tick(delta)
	if wave_director.is_prep_phase() or wave_director.is_wave_phase():
		economy.tick(delta)
	if Input.is_action_just_pressed("ready_round") and wave_director.is_prep_phase():
		wave_director.ready_round()
	# Hold-to-retreat: while the key is down, units ignore enemies. The
	# setter short-circuits when the value is unchanged, so polling every
	# frame is fine.
	GameState.set_retreat(Input.is_action_pressed("toggle_retreat"))
	_tick_signature_cooldown(delta)
	if Input.is_action_just_pressed("cast_signature"):
		_try_cast_signature()
	# Hero can WASD while the player is dragging an ability card with the
	# mouse — refresh the aim line each frame so the start point tracks them.
	if _aim_line != null:
		_update_aim_line()

func _on_play_requested(card_id: String, world_pos: Vector2) -> void:
	card_system.play_card_at(card_id, world_pos, _current_phase_name(), economy.balance)

func _on_drag_started(card_id: String, world_pos: Vector2) -> void:
	var card: Dictionary = Cards.get_card(card_id)
	if card.is_empty():
		return
	match card.kind:
		"unit", "building", "resource":
			# All non-ability kinds just require any drop inside the sector;
			# the highlight reads as "anywhere on the floor is legal".
			sector.set_deploy_highlight(true)
		"ability":
			_aim_card_id = card_id
			_aim_target = world_pos
			_spawn_aim_line()

func _on_drag_moved(_card_id: String, world_pos: Vector2) -> void:
	_aim_target = world_pos
	_update_aim_line()

func _on_drag_ended() -> void:
	# Both indicators clear regardless of which kind opened them — cheap and
	# avoids leaving stragglers if the card kind ever changes mid-drag.
	sector.set_deploy_highlight(false)
	_clear_aim_line()

func _spawn_aim_line() -> void:
	_clear_aim_line()
	if hero == null or not is_instance_valid(hero):
		return
	_aim_line = Line2D.new()
	_aim_line.width = 6.0
	var accent := DesignTokens.core_color(GameState.hero_id)
	_aim_line.default_color = Color(accent.r, accent.g, accent.b, 0.55)
	# Above sector + units but below the dragged card (which lives on a
	# CanvasLayer, so always above world content regardless of z_index).
	_aim_line.z_index = 4
	add_child(_aim_line)
	_update_aim_line()

func _update_aim_line() -> void:
	if _aim_line == null or hero == null or not is_instance_valid(hero):
		return
	# Clamp the endpoint to the sector so the line stops at a sensible point
	# when the drag wanders into the HUD or hand strip.
	var endpoint := _aim_target
	endpoint.x = clamp(endpoint.x, float(Sectors.SECTOR_LEFT), float(Sectors.SECTOR_RIGHT))
	endpoint.y = clamp(endpoint.y, float(Sectors.SECTOR_TOP), float(Sectors.SECTOR_BOTTOM))
	_aim_line.clear_points()
	_aim_line.add_point(hero.position)
	_aim_line.add_point(endpoint)

func _clear_aim_line() -> void:
	_aim_card_id = ""
	if _aim_line != null and is_instance_valid(_aim_line):
		_aim_line.queue_free()
	_aim_line = null

func _current_phase_name() -> String:
	if wave_director.is_prep_phase():
		return "prep"
	if wave_director.is_wave_phase():
		return "wave"
	return "other"

func _on_card_played(card: Dictionary, world_pos: Vector2) -> void:
	# Building cards no-op when the production node is already at max tier;
	# don't charge the player for a card that did nothing. CardSystem can't
	# see economy.production_tier, so the refund-style guard lives here.
	if card.kind == "building" and economy.production_tier >= Economy.PRODUCTION_TIERS.size():
		return
	# Pay cost first; the logic layer has already validated phase + balance.
	if int(card.cost) > 0:
		economy.spend(int(card.cost))
	match card.kind:
		"unit":
			_spawn_unit(card.payload.unit_id, world_pos)
		"building":
			_place_or_upgrade_building(world_pos)
		"resource":
			economy.add(int(card.payload.coin_delta))
		"ability":
			_resolve_ability(card.payload.ability_id, world_pos)

func _spawn_unit(unit_id: String, world_pos: Vector2) -> void:
	var u: Node2D = UnitScene.instantiate()
	u.configure(unit_id)
	u.position = world_pos
	# Each unit picks a stable formation slot relative to the leader so a
	# growing army doesn't collapse onto a single point. Random offset is
	# fine for v0; a tighter ring layout can come later.
	var offset := _random_formation_offset()
	u.bind_leader(hero, offset)
	add_child(u)

func _random_formation_offset() -> Vector2:
	# Slot is biased behind/below the leader (negative x) so units flank
	# the spawn pad rather than crowd Buffalo's nose.
	var x := randf_range(-72.0, -16.0)
	var y := randf_range(-56.0, 56.0)
	return Vector2(x, y)

func _place_or_upgrade_building(world_pos: Vector2) -> void:
	if building_node != null and is_instance_valid(building_node):
		var tier: int = economy.place_or_upgrade_node()
		building_node.set_tier(tier)
		return
	economy.place_or_upgrade_node()
	var b: Node2D = BuildingScene.instantiate()
	b.position = world_pos
	add_child(b)
	building_node = b

func _try_cast_signature() -> void:
	# Q-cast: gate on phase, hero alive, and cooldown ready. Mouse position
	# becomes the cast target — same convention as the card-drop flow.
	if not wave_director.is_wave_phase():
		return
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	if _signature_cd_remaining > 0.0:
		return
	var hero_def: Dictionary = Heroes.ALL.get(GameState.hero_id, Heroes.Buffalo)
	var ability_id: String = hero_def.get("signatureAbilityId", "")
	if ability_id.is_empty():
		return
	var target := get_global_mouse_position()
	# Clamp the target inside the sector so a Q while the mouse is over the
	# HUD or hand strip still resolves at a sensible point in the arena.
	target.x = clamp(target.x, float(Sectors.SECTOR_LEFT), float(Sectors.SECTOR_RIGHT))
	target.y = clamp(target.y, float(Sectors.SECTOR_TOP), float(Sectors.SECTOR_BOTTOM))
	_show_cast_pulse(hero.position)
	_resolve_ability(ability_id, target)
	var cooldown: float = float(hero_def.get("signatureCooldown", 5.0))
	_signature_cd_max = cooldown
	_signature_cd_remaining = cooldown
	GameState.set_signature_cooldown(_signature_cd_remaining, _signature_cd_max)

func _tick_signature_cooldown(delta: float) -> void:
	if _signature_cd_remaining <= 0.0:
		return
	_signature_cd_remaining = max(0.0, _signature_cd_remaining - delta)
	GameState.set_signature_cooldown(_signature_cd_remaining, _signature_cd_max)

func _reset_signature_cooldown() -> void:
	_signature_cd_remaining = 0.0
	_signature_cd_max = 0.0
	GameState.set_signature_cooldown(0.0, 0.0)

func _show_cast_pulse(at: Vector2) -> void:
	# Brief radial flash centered on the caster — sells the input even before
	# the ability's own AoE visual lands. Sound stub TODO when audio comes in.
	var pulse := Polygon2D.new()
	const SEGMENTS := 24
	const START_RADIUS := 18.0
	var pts := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		pts.append(Vector2(cos(a), sin(a)) * START_RADIUS)
	pulse.polygon = pts
	pulse.position = at
	var accent := DesignTokens.core_color(GameState.hero_id)
	pulse.color = Color(accent.r, accent.g, accent.b, 0.55)
	pulse.z_index = 6
	add_child(pulse)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(pulse, "scale", Vector2(2.4, 2.4), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(pulse, "modulate:a", 0.0, 0.28)
	t.chain().tween_callback(pulse.queue_free)

func _resolve_ability(ability_id: String, target_pos: Vector2) -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_downed:
		return
	var effects := AbilityResolver.resolve(ability_id, hero.position, target_pos)
	for fx in effects:
		match fx.kind:
			"damage_in_capsule":
				_apply_capsule_damage(fx)
				_show_charge_line(fx.from, fx.to, fx.width)
			"damage_in_cone":
				_apply_cone_damage(fx)
				_show_dive_cone(fx.from, fx.direction, fx.length, fx.half_angle)
			"dash_and_strike":
				_apply_dash_and_strike(fx)

func _apply_capsule_damage(fx: Dictionary) -> void:
	var from: Vector2 = fx.from
	var to: Vector2 = fx.to
	var width: float = float(fx.width)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if _point_in_capsule(e.position, from, to, width * 0.5):
			e.damage(float(fx.damage))
			if is_instance_valid(e):
				e.apply_knockback(fx.direction, float(fx.knockback))

func _point_in_capsule(p: Vector2, a: Vector2, b: Vector2, radius: float) -> bool:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq <= 0.0001:
		return p.distance_to(a) <= radius
	var t: float = clamp((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var nearest: Vector2 = a + ab * t
	return p.distance_to(nearest) <= radius

func _apply_cone_damage(fx: Dictionary) -> void:
	var apex: Vector2 = fx.from
	var dir: Vector2 = fx.direction
	var length: float = float(fx.length)
	var half_angle: float = float(fx.half_angle)
	var cos_threshold := cos(half_angle)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		var to_enemy := e.position - apex
		var dist := to_enemy.length()
		if dist <= 0.0001 or dist > length:
			continue
		# Inside the cone if the angle between dir and (enemy - apex) is
		# under half_angle. Compare cosines so we don't pay for an arccos.
		if to_enemy.normalized().dot(dir) < cos_threshold:
			continue
		e.damage(float(fx.damage))
		if is_instance_valid(e):
			e.apply_knockback(dir, float(fx.knockback))

func _show_dive_cone(apex: Vector2, dir: Vector2, length: float, half_angle: float) -> void:
	# A faction-tinted fan that fades out — same lifetime as the charge line.
	var poly := Polygon2D.new()
	var points := PackedVector2Array()
	points.append(apex)
	const SEGMENTS := 12
	var start := dir.rotated(-half_angle)
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var v := start.rotated(half_angle * 2.0 * t)
		points.append(apex + v * length)
	poly.polygon = points
	var accent := DesignTokens.core_color(GameState.hero_id)
	poly.color = Color(accent.r, accent.g, accent.b, 0.5)
	poly.z_index = 5
	add_child(poly)
	var tween := create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.45)
	tween.tween_callback(poly.queue_free)

const SNATCH_DASH_DURATION := 0.12

func _apply_dash_and_strike(fx: Dictionary) -> void:
	# Tween the hero to the dash endpoint so the strike reads as a real
	# pounce rather than a teleport, then resolve damage. Damage is applied
	# from the endpoint so a Fox who dashes through gets backstab credit.
	var to: Vector2 = fx.to
	var radius: float = float(fx.radius)
	var base_damage: float = float(fx.damage)
	var backstab_mult: float = float(fx.backstab_multiplier)
	hero.set_scripted_motion(true)
	var t := create_tween()
	t.tween_property(hero, "position", to, SNATCH_DASH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_release_scripted_motion.bind(hero))
	t.tween_callback(_resolve_snatch_strike.bind(to, radius, base_damage, backstab_mult, fx.direction))
	_show_dash_trail(fx.from, to)

func _resolve_snatch_strike(end_pos: Vector2, radius: float, base_damage: float,
		backstab_mult: float, dir: Vector2) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if e.position.distance_to(end_pos) > radius:
			continue
		# Enemies face left (toward the core). The hero is "behind" if they
		# ended up on the enemy's right — i.e. the hero passed through it.
		var is_backstab: bool = end_pos.x >= e.position.x
		var dmg := base_damage * (backstab_mult if is_backstab else 1.0)
		e.damage(dmg)
		if is_instance_valid(e):
			# Light shove away from the strike to sell the hit. Direction is
			# the dash vector — punch them along the path Fox came in on.
			e.apply_knockback(dir, 24.0 if is_backstab else 12.0)

func _show_dash_trail(from: Vector2, to: Vector2) -> void:
	# A thin streak from start to end that fades in under a quarter-second.
	# Lighter than the Buffalo charge line so the two abilities read as
	# distinct silhouettes (line AoE vs. precision dash).
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = 6.0
	var accent := DesignTokens.core_color(GameState.hero_id)
	line.default_color = Color(accent.r, accent.g, accent.b, 0.7)
	line.z_index = 5
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.3)
	tween.tween_callback(line.queue_free)

func _show_charge_line(from: Vector2, to: Vector2, width: float) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = width
	var accent := DesignTokens.core_color(GameState.hero_id)
	line.default_color = Color(accent.r, accent.g, accent.b, 0.55)
	line.z_index = 5
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.45)
	tween.tween_callback(line.queue_free)

func _on_enemy_due(enemy_type: String, slot_index: int) -> void:
	var e: Node2D = EnemyScene.instantiate()
	e.configure(enemy_type)
	# Stagger Y across the sector band so enemies arrive in a spread.
	var band_top := Sectors.SECTOR_TOP + 64
	var band_bot := Sectors.SECTOR_BOTTOM - 64
	var y := band_top + (slot_index * 53) % int(band_bot - band_top)
	e.position = Vector2(Sectors.ENEMY_ENTRY_X, y)
	e.died.connect(func(_n): wave_director.note_enemy_killed())
	e.reached_core.connect(_on_enemy_reached_core)
	add_child(e)
	wave_director.note_enemy_spawned()

func _on_enemy_reached_core(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	sector.damage_core(float(enemy.data.damage))
	# After landing the hit, the enemy is consumed — they die into the core.
	wave_director.note_enemy_killed()
	enemy.queue_free()

func _on_round_started(_round_index: int) -> void:
	GameState.set_phase(GameState.Phase.PREP)
	GameState.round_index = _round_index
	card_system.start_round()

func _on_wave_started(_round_index: int, _composition: Dictionary) -> void:
	GameState.set_phase(GameState.Phase.WAVE)
	# Info-asymmetry rule (hi-fi v3 §2A/§2B + signoff): the first-hit player
	# sees full composition in a private side panel. Single-player resolves
	# "first-hit player" to the local hero, so the panel surfaces here every
	# wave. M4 will gate this on per-player engagement.
	if wave_comp_panel != null:
		wave_comp_panel.show_for(_round_index, _composition, GameState.hero_id)

func _on_wave_ended(_round_index: int, victory: bool) -> void:
	GameState.set_phase(GameState.Phase.DEBRIEF)
	# Sweep any survivors so the debrief is clean.
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	_reset_signature_cooldown()
	if wave_comp_panel != null:
		wave_comp_panel.hide_panel()
	if help_banner != null:
		help_banner.clear_help()
	# A loss skips the reset — the run is ending, end screen takes over.
	if victory:
		_reset_to_base()

const RESET_DURATION := 0.6

func _reset_to_base() -> void:
	# Tween Buffalo and any surviving units back to the spawn pad area.
	# AI / input stays off on each entity for the duration of the tween.
	# Revive a downed hero immediately — HP and state restore as they walk back.
	if hero == null or not is_instance_valid(hero):
		# No hero in the tree (mid-rebuild / edge case). Units fall back to
		# the spawn pad anchor directly so they still regroup.
		var anchor := Sectors.SPAWN_PAD_CENTER
		for n in get_tree().get_nodes_in_group("units"):
			var u := n as Node2D
			if u == null or not is_instance_valid(u):
				continue
			_tween_back(u, anchor + u.formation_offset)
		return
	hero.revive()
	var hero_target: Vector2 = hero.spawn_position()
	_tween_back(hero, hero_target)
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Node2D
		if u == null or not is_instance_valid(u):
			continue
		_tween_back(u, hero_target + u.formation_offset)

func _tween_back(node: Node2D, target: Vector2) -> void:
	# Helper extracted so each tween captures its own `node` by argument
	# rather than via a loop-variable closure.
	node.set_scripted_motion(true)
	var t := create_tween()
	t.tween_property(node, "position", target, RESET_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_release_scripted_motion.bind(node))

func _release_scripted_motion(node: Node) -> void:
	if is_instance_valid(node):
		node.set_scripted_motion(false)

func _on_hero_downed() -> void:
	hud.show_banner("Hero is down — hold the line!", 2.5)

func _on_core_destroyed() -> void:
	wave_director.note_core_destroyed()

func _on_run_complete() -> void:
	GameState.set_phase(GameState.Phase.RUN_COMPLETE)
	SaveSystem.record_run_end(GameState.hero_id, true, GameState.round_index)
	end_screen.show_victory()

func _on_run_ended() -> void:
	GameState.set_phase(GameState.Phase.RUN_ENDED)
	SaveSystem.record_run_end(GameState.hero_id, false, GameState.round_index)
	end_screen.show_defeat()

func _on_restart_requested() -> void:
	# "Try again" — same hero, fresh run. Clear transients; _start_run
	# re-publishes core/hero HP itself.
	_clear_run_transients()
	end_screen.visible = false
	_start_run()

func _on_back_to_lodge_requested() -> void:
	# "Back to the lodge" — every run ends in the warm room, victory or
	# defeat (BUF-112). Tear down the hero so a different pick instantiates
	# fresh from the Lodge, and clear all run transients before the curtain.
	# Persist the lodge-return so a relaunch doesn't lose the pick history.
	SaveSystem.note_lodge_visit(GameState.hero_id)
	_clear_run_transients()
	if hero != null and is_instance_valid(hero):
		hero.queue_free()
		hero = null
	end_screen.visible = false
	_open_lodge()

func _clear_run_transients() -> void:
	for n in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(n): n.queue_free()
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n): n.queue_free()
	if building_node != null and is_instance_valid(building_node):
		building_node.queue_free()
		building_node = null
	# Belt-and-suspenders for the drag indicators: if the player got to the
	# end screen mid-drag (rare), clear them before the next run wires up.
	if sector != null and is_instance_valid(sector):
		sector.set_deploy_highlight(false)
	_clear_aim_line()
