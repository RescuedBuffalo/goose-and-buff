# Claude Code Prompt — Godot Prototype Pivot

> Paste this into Claude Code (with the project folder open) when you're ready to start the prototype. The goal is **validation, not a finished game**. We're answering three questions: (1) does the illustrated 2D art direction work? (2) does the new card-based mechanic feel good? (3) is Godot's workflow sustainable? If yes → we pivot the whole project. If no → we scrap this and adjust the Roblox version.

---

## Context

This is a parallel-branch prototype of an existing project. The project is **The Long Watch** (working name "Goose-and-Buff") — a private 3-player co-op roguelite for three friends. The existing implementation is in Roblox; we're testing whether to pivot to Godot for a hand-drawn 2D aesthetic (Hades / Spiritfarer / Root references).

Read these files before doing anything else:

- `VISION.md` — pillars, philosophy, Valorant-shaped role trinity (Goose / Buffalo / Fox)
- `v0.1-SPEC.md` — buildable contract for the first playable
- `README.md` — architecture rules, voice rules, conventions
- `units-data.md` — the 9 themed units (Gosling/Heron/Swan, Calf/Ostrich/Longhorn, Kit/Lynx/Badger)
- `C:\Users\aidan\Downloads\design\README.md` — design system: colors, type, voice rules, visual foundations
- `C:\Users\aidan\Downloads\design\colors_and_type.css` — canonical token values
- `C:\Users\aidan\Downloads\design\src\shared\Data\Sectors.lua` — canonical hero color palette
- `C:\Users\aidan\Downloads\design\assets\totems\*.svg` — Goose, Buffalo, Fox, Val totem marks (Godot imports SVG natively — use these directly, do not regenerate)

These docs are the source of truth for design intent, hero/unit/sector data, and voice. **Don't reinvent any of it.** Port verbatim where you can, translate syntactically where you must.

## Where to put the work

Create a sibling subfolder: `godot-prototype/`

Do NOT touch:
- The existing Roblox source on disk (whatever Rojo is syncing from)
- The Linear project
- Any of the existing markdown docs

This prototype lives entirely in `godot-prototype/`. If we decide to merge it, we'll deal with that as a separate operation. If we decide to scrap it, we delete the folder.

## Engine and stack

- **Godot 4** (latest stable). GDScript for scripts. Use `@export` for designer-tunable values.
- **2D-only project.** No 3D nodes anywhere. The art direction is hand-drawn 2D.
- **No external dependencies** unless absolutely necessary. Godot's built-ins should cover everything in this scope.
- **Single player** for the prototype. Multiplayer is parked. Do not implement Godot's MultiplayerAPI in this prototype — it adds infrastructure complexity that distracts from the questions we're trying to answer.

## Scope — what to build

A single-player vertical slice of a defense round. Tight enough to ship in one evening of focused work.

### Hero
**Buffalo only.** One hero, the player's character. Use Buffalo's stats from `Heroes.lua`:
- baseHealth: 160, moveSpeed: 12 (translate moveSpeed to whatever Godot units feel right at 2D scale)
- Use Buffalo's totem SVG as the character sprite for v0
- Buffalo's signature ability: **Charge** — line AoE, knockback. Per `Abilities.lua` if it's there, otherwise use the spec in `v0.1-SPEC.md`.

### Sector / arena
A single Buffalo sector, top-down 2D view. Use Buffalo's canonical floor color (`Color3.fromRGB(150, 100, 70)` translated to Godot Color) for the floor. Put the **Core** at one end (use Buffalo's core color — `(110, 70, 40)`) and the spawn pad at the other. Enemies enter from beyond the core's far edge and walk toward the core.

### Card mechanic — the new core loop

This is the **primary thing to validate** in this prototype.

**Hand-of-cards model.** The player has a hand of cards visible at the bottom of the screen. At the start of each round (prep phase), draw 5 cards from the deck. The player drags cards from hand onto the sector to play them. Played cards go to discard. At end of round, shuffle discard into deck and redraw 5.

**Starter deck (15 cards for v0):**
- 4× **Calf** (Buffalo Light unit) — cost 28 coin
- 3× **Ostrich** (Buffalo Ranged unit) — cost 40 coin
- 2× **Longhorn** (Buffalo Heavy unit) — cost 80 coin
- 3× **Production Node** (building, cost 50 coin, generates 5 coin/sec) — only one can exist at a time, additional plays upgrade tier
- 2× **Buffalo Charge** (signature ability) — cost 0 coin, plays during wave phase
- 1× **Stockpile** (resource card, gives +30 coin instantly)

**Card kinds and behaviors:**
- **Unit cards**: drag onto your sector during prep. Pays cost. Unit spawns at the drop position and walks toward enemy entry, engaging on sight.
- **Building cards**: drag onto your sector during prep. Pays cost. Building spawns at the drop position. Production Node generates coin over time. Only one building max in v0.
- **Ability cards**: stay in hand until activated. Click during wave phase to enter targeting mode (line-aim for Charge), then click to cast. Charge does AoE damage along a line and applies knockback. Cooldown applies after use, but in v0 we treat ability cards as one-shot per draw — once played, they go to discard and return next round.
- **Resource cards**: click to play instantly. Stockpile adds +30 coin to balance.

**Card art for v0:**
- Use the design system token colors per faction
- Each card is a Frame with: hero totem in top-left (use the SVG), card name, cost (coin icon + number, tabular numerals), description, flavor line (from `units-data.md` for units), and a placeholder illustrated portrait area (gradient fill in the appropriate hero accent color is fine — we'll replace with real illustrations later)
- Card size: ~200×280px at canonical resolution
- Use `--font-display` for the card name, `--font-body` for description, `--font-mono` for cost

### Round structure

Two phases, looping:

1. **Prep phase** (30 seconds, timer visible top-right): player draws hand, plays cards onto sector, can move Buffalo around the sector freely. Coin generates from Production Node if one exists. When timer hits 0 OR player presses "Ready", advance to wave phase.
2. **Wave phase**: 8 enemies spawn at the entry edge and walk toward the core. Use enemy stats from the existing `Waves.lua` `GruntMelee` archetype (HP 30, damage 6, attack range 3). Buffalo can move and use ability cards. Deployed units engage automatically. When all enemies dead OR core HP <= 0, advance to debrief.
3. **Debrief**: 5 second buffer with a result message, then loop back to prep with hand reshuffled.

After 3 successful waves → "RUN COMPLETE" screen. After core dies → "RUN ENDED" screen. Single button to restart on either.

### Voice and copy

Apply the voice rules from `README.md` and the design system README:
- Sentence case for everything except wave-banner shouts
- No emoji
- Hero names always written in full
- HP shown as `124 / 160`, timers as `0:24`
- Tone: warm, opinionated, never ironic

Wave-banner shout text: `"WAVE 2 — HOLD THE LINE"` style. Round end: `"We held."` for victory, `"The line broke."` for defeat. Don't make up new copy patterns; if a moment doesn't have a defined string, use the simplest sentence-case version.

## Architecture — translate the conventions

The existing project has a load-bearing split between pure logic, Roblox-aware adapters, and pure data. **Preserve this discipline in Godot.** It's the reason we can pivot at all.

### Folder structure (suggested)

```
godot-prototype/
    project.godot
    addons/                       (none for v0)
    scenes/
        main.tscn                 (root scene)
        sector.tscn               (the playable arena)
        hero.tscn                 (Buffalo character)
        unit.tscn                 (one scene, polymorphic on archetype)
        building.tscn
        enemy.tscn
        ui/
            hand.tscn             (card hand display)
            card.tscn             (single card)
            hud.tscn              (HP, coin, timer, wave)
            end_screen.tscn
    scripts/
        logic/                    -- pure GDScript, no node references
            wave_director.gd
            ability_resolver.gd
            card_system.gd
            economy.gd
        adapters/                 -- bridge logic to scene tree
            wave_spawner.gd
            unit_spawner.gd
            input_adapter.gd
            ui_renderer.gd
        ui/
            card_widget.gd
            hand_widget.gd
            hud_widget.gd
        autoload/
            design_tokens.gd      (singleton)
            game_state.gd         (singleton holding current run state)
    data/                         -- pure data resources
        heroes.gd                 (constants or Resource files)
        units.gd
        cards.gd                  (the new one — card definitions)
        sectors.gd
        waves.gd
        enemies.gd
    assets/
        totems/                   (copied from design/assets/totems/)
        cards/                    (placeholder card frames)
        ui/                       (HUD chrome, fonts)
```

### Architecture rules (mirror the existing project)

- **`scripts/logic/*` is pure GDScript.** No `get_node()`, no scene-tree reads, no `Engine.get_singleton()` for engine state. State machines and pure functions only. These modules run identically whether or not a scene is loaded — easy to unit-test, easy to port.
- **`scripts/adapters/*` is where Godot APIs are allowed.** Adapters subscribe to logic-module signals and translate them into scene-tree mutations.
- **`data/*.gd` is plain dictionaries / arrays / constants.** No logic. Mirror the existing `Heroes.lua`, `Sectors.lua`, `units-data.md` exactly — same field names, same values where they translate cleanly.
- **`autoload/design_tokens.gd` is the canonical color/type/spacing source.** Mirror `colors_and_type.css` 1:1. Every UI piece reads tokens from here. **Never hardcode a Color or font size.**

### Signal patterns

Use Godot signals for the same event-emission pattern WaveDirector uses in the existing project. `wave_director.gd` should emit `round_started(round_index)`, `wave_started(enemies_data)`, `round_ended(round_index)`. The `wave_spawner` adapter listens and creates enemy nodes.

`card_system.gd` should emit signals like `hand_drawn(cards)`, `card_played(card_id, position)`, `card_discarded(card_id)`. The `ui_renderer` listens and updates the hand widget; the appropriate spawner listens for unit/building plays.

## Validation criteria — when is this prototype done?

The prototype is "done" when you can run it locally and:

- [ ] Buffalo character is on screen, controllable with WASD movement
- [ ] Buffalo's totem SVG renders as the character sprite (placeholder is fine — just the SVG, no animation)
- [ ] Sector floor and core render in their canonical Buffalo colors
- [ ] Hand of 5 cards visible at the bottom; cards have the correct content + colors per design tokens
- [ ] Player can drag-drop a unit card onto the sector during prep → unit spawns + card goes to discard
- [ ] Player can drag-drop a building card → Production Node appears, generates coin
- [ ] Player can play the Charge ability card during wave phase → line AoE damages enemies
- [ ] Wave timer ticks down, enemies spawn at the entry edge and walk toward core
- [ ] Deployed units engage enemies; enemies attack core if they reach it
- [ ] Round ends correctly (3 waves cleared = victory; core HP 0 = defeat)
- [ ] HUD shows: Buffalo HP, coin balance, current round, wave timer — all using design tokens
- [ ] Voice rules followed in every visible string
- [ ] No emoji, sentence case, full hero name, tabular numerals on HP and timers

That's it. We are not validating: multiplayer, enemy variety, three full hero kits, polish, animations, sound, win-condition variety.

## What NOT to build

These are tempting and out of scope:
- **Multiplayer.** Even a stub. Don't import `MultiplayerSpawner` or `MultiplayerSynchronizer`. Single-player only.
- **Goose or Fox playable.** Buffalo only.
- **More than one sector / arena layout.** One sector.
- **Skill trees.** Cards replace this anyway in the long run; don't port the skill-tree logic.
- **Real animations.** Static sprites with one or two tweens for feedback (card play, hit flash) is enough.
- **Real character illustrations.** Use the totem SVGs as character sprites for v0. Real illustrations come later, after we decide if the prototype is worth merging.
- **Sound design.** Silence is fine for the prototype.
- **Save / load.** Each run is fresh.
- **Steam integration, itch.io export config, or any distribution work.** Run locally only.

If you find yourself wanting to add any of the above to "make it feel real," resist. The prototype is for answering three specific questions, not shipping a game.

## Voice rules — apply throughout the codebase too

The design system's voice rules apply to in-game text. They also apply to **any text that ships in the build** — error messages the player might see, debug overlays during play, the build-info display, etc. Sentence case, no emoji, warm but not cute.

Comments and code identifiers are exempt — comment in whatever style helps the next reader.

## Reporting back

When the prototype is runnable, write a short `godot-prototype/PROTOTYPE-NOTES.md` covering:

- What ships and what's stubbed
- Any deviation from this spec, with reasoning
- Specific things you'd flag for the design/PM review (e.g., "the card-drag UX feels off when the sector is small — recommend resizing the sector or scaling the cards")
- Open questions for the merge decision

Keep it under 300 words. The notes are for triage, not documentation.

## Tone for the work

The architecture discipline matters because this is a *real* pivot test. If the prototype's logic is tangled with Godot scene-tree calls, we won't be able to evaluate cleanly whether the engine is working for us — we'll only be able to evaluate whether *that specific implementation* is. Keep the layers clean and we get an honest answer.

Build the smallest, cleanest version that demonstrates the three questions. Resist the urge to make it impressive.
