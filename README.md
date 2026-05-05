# Goose-and-Buff *(working title: The Long Watch)*

A private 3-player co-op roguelite for Aidan, Goose, and Beau. Animal-totem heroes, card-driven economy + combat, sequential info-asymmetric waves (in multiplayer), voice comms is the gameplay.

## Where things live

- **Game code** lives in the Godot project at the repo root. Open `project.godot` in Godot 4 to run. The current build is the **isometric tile rebuild** — see [`docs/PROTOTYPE-NOTES.md`](docs/PROTOTYPE-NOTES.md) for the Phase 1 status and what's stubbed.
- **Design docs**: [`docs/VISION.md`](docs/VISION.md) for pillars and philosophy. [`docs/v0.1-SPEC.md`](docs/v0.1-SPEC.md) for what shipped in the v0.1 prototype + what's next.
- **Design system**: `design/` (the Long Watch design system bundle). Source of truth for colors, type, voice. `colors_and_type.css` mirrors the in-engine `DesignTokens` autoload 1:1. Read `design/README.md` before doing UI work.
- **Top-down v0.1 prototype** (archived for reference): [`archive/godot-top-down/`](archive/godot-top-down/) — the flat-arena Buffalo wave-defense build that the tile rebuild replaced. Standalone Godot project; run by opening its own `project.godot`.
- **Roblox-era source** (archived for history): `archive/roblox/`.
- **Active work**: [Linear — buffalo-and-goose](https://linear.app/buffalo-studios/project/buffalo-and-goose-593efd9062a8). Milestones M1 (Solo loop) → M2 (30-min depth) → M3 (Visual polish + audio) → M4 (Multiplayer).

## Project layout

```
project.godot                   (tile rebuild — canonical)
scenes/
    main.tscn                   root scene
    sector.tscn                 isometric TileMapLayer + AStarGrid2D
    hero.tscn                   playable character (tile-pathfinds)
    unit.tscn                   AI-controlled deployed unit
    building.tscn               production node
    enemy.tscn                  enemy (polymorphic on archetype)
    ui/
        hand.tscn               card hand display, tile-snap drop targeting
        card.tscn               single card
        hud.tscn                HP / coin / timer / wave / phase
        end_screen.tscn         victory / defeat
scripts/
    logic/                      pure GDScript, no scene-tree references
        wave_director.gd        round + wave scheduling
        ability_resolver.gd     pure-data effect computation
        card_system.gd          deck / hand / discard / draw
        economy.gd              coin generation + spending
    adapters/                   bridge logic to scene tree
        main.gd                 the boot-and-wire script
        sector.gd               TileMapLayer + AStarGrid2D, tile <-> world helpers
        hero.gd, unit.gd, enemy.gd, building.gd
    autoload/                   project-wide singletons
        design_tokens.gd        colors, fonts, sizes, motion
        game_state.gd           current run state
data/                           plain-data resources, no logic
    heroes.gd
    units.gd                    9 themed units across 3 factions
    cards.gd                    starter decks per hero
    sectors.gd                  tile-grid geometry + canonical hero palette
    waves.gd                    wave compositions + enemy archetypes
    enemies.gd                  enemy stats
assets/
    totems/                     hero/Val totem marks (SVG / PNG)
    fonts/                      Young Serif / Nunito / JetBrains Mono (M3)
archive/
    godot-top-down/             v0.1 flat-arena prototype, pre-tile-pivot
    roblox/                     Roblox-era source
```

## Architecture rules (load-bearing)

The codebase is split into three layers on purpose. Code that violates the split creates work later — both when iterating and if we ever rebuild in another engine. This discipline is what made the Roblox→Godot pivot cheap; preserve it.

1. **Pure logic** in `scripts/logic/*`. No scene-tree references — no `get_node`, no `get_tree`, no `Engine.get_singleton` for engine state. State machines and pure functions only — inputs and outputs.
2. **Adapters** in `scripts/adapters/*`. This is where Godot APIs are allowed. Adapters subscribe to logic-module signals and translate them into scene-tree mutations.
3. **Pure data** in `data/*`. Plain Luau-flavored GDScript dictionaries, arrays, constants. Easy to inspect, balance, copy-paste between projects. No logic.

Project-wide singletons live in `scripts/autoload/`. The `design_tokens.gd` autoload is the canonical color/type/spacing source — every UI piece reads tokens from it.

## Existing APIs — reuse, don't re-derive

When picking up an issue, check whether the system already exists before writing it:

- `WaveDirector` (signal-based). Emits `round_started(round_index)`, `wave_started(enemies_data)`, `round_ended(round_index)`. Adapters listen and spawn.
- `WaveDirector.tick(dt)` — pure dt-driven. The boot adapter wraps it in `_process` from a node; never put `_process` inside logic.
- `AbilityResolver.resolve(ability_id, caster_state, targeting_payload)` — produces a list of pure-data effects. Adapters apply effects to the scene.
- `CardSystem.new(hero_id)`, `.draw(n)`, `.play(card_id, drop_position)`, `.discard()`, `.shuffle()` — deck / hand / discard model.
- `Economy.new(hero_id)`, `.tick(dt)`, `.spend(amount)`, `.upgrade_production()` — coin generation and spending.
- `DesignTokens.Hero[hero_id].floor / .core / .ink`, `.Night[0..4]`, `.Parchment[0..2]`, `.HP.full/warn/crit`, `.Core.shield/down`, `.XP`, `.Gold`, `.FontSize.*`, `.Space[1..9]`, `.Radius[1..4]`, `.Tween.out/pounce/buffalo` — the full design system. **Use these for any UI work.** Never hardcode a Color or font size.
- `Sectors.by_hero[hero_id].center / .floor_color / .core_color`, `.spawn_pad_offset`, `.core_offset`, `.core_size`, `.core_health`, `.divider_color`, `.spectator` — arena layout. Read by the WorldBuilder logic in the boot adapter.

## Conventions and anti-patterns

- **Don't put `await get_tree().create_timer(x).timeout` inside `scripts/logic/*`.** Time progression is `tick(dt)`-driven. Sleeps belong in adapters / scene scripts.
- **Don't hardcode colors, fonts, or sizes.** Always pull from `DesignTokens`. The design system at `design/colors_and_type.css` is the upstream source of truth — `design_tokens.gd` mirrors it. Adding a new color means adding it to *both* (and ideally to `Sectors.lua` first if it's hero-related).
- **Don't invent hero colors.** `DesignTokens.Hero` and `Sectors.by_hero` are the only legal sources for Goose / Buffalo / Fox / Val color values.
- **Don't broadcast wave composition automatically in multiplayer.** First-hit-only visibility is the spine mechanic. The reveal logic lives in `WaveDirector.get_visible_state_for_player(player_id)` — render that state, don't re-derive who sees what.
- **Don't restructure existing signal wiring** when adding to an adapter. The pattern is: an adapter `attach`-es to a logic module and connects to its signals. Replace placeholder behavior inside callbacks; don't rebuild the wiring.

## Voice rules (non-negotiable, from design system)

These apply to every string the player sees in-game:

- **Sentence case** for UI: buttons, headers, labels. ("Start a run", not "START A RUN".)
- **ALL-CAPS only** for short eyebrow labels and wave-banner shouts ("WAVE 3 — FOX'S TURN").
- **No emoji in UI.** The animal totems are the emoji.
- **Hero names always written in full**: Goose, Buffalo, Fox, Val. No "G", "Buf", "F" — those are Discord, not the game.
- **HP shown as `124 / 160`**, never `124/160`. **Timers as `0:24`**, never `24s`.
- **Tone**: warm, opinionated, never ironic. The voice is the inside-joke book club, not the marketing deck.
- **Em dashes are fine.** Single exclamation mark only — never two.
- Default voice: **second-person, warm**. The game itself can speak in first-person plural for solidarity moments ("we held the line").

## Workflow for picking up an issue

1. Read the Linear issue. Note the acceptance criteria and any "out of scope" notes.
2. Identify which layer the work belongs to: pure logic, adapter, data, or scene/UI.
3. Check the "Existing APIs" section above — reuse before re-deriving.
4. For UI work, also read `design/README.md` and use `DesignTokens` for every value.
5. Implement. Use the Godot MCP for live iteration when available.
6. Verify: run the relevant scene, watch the console, take a screenshot.
7. Comment on the Linear issue with what shipped, what was descoped, and any open questions for the PM conversation.

## Style

- GDScript, server-authoritative once multiplayer lands (M4).
- Prefer signals over polling.
- Prefer composition over inheritance — most things should be a scene + script combo.
- Comments explain *why*, not *what*. Code should read naturally enough that the *what* is obvious.
- Keep public functions small and named for their effect. Internal helpers prefixed with `_`.

## History

This project pivoted from Roblox → Godot in May 2026 to support a hand-drawn 2D illustrated aesthetic (Hades / Spiritfarer / Root references). The Roblox-era source has been canceled in Linear; the architectural discipline carried over and the data and pure-logic patterns ported cleanly.

In May 2026 the Godot build pivoted again — from a flat top-down arena to an **isometric tile grid** to support seasonal terrain, exploration, and survival mechanics planned for Phase 2+. The v0.1 top-down build is preserved at [`archive/godot-top-down/`](archive/godot-top-down/) so the before/after comparison stays cheap. The pure-logic and data layers ported verbatim through the tile pivot — see [`docs/PROTOTYPE-NOTES.md`](docs/PROTOTYPE-NOTES.md).
