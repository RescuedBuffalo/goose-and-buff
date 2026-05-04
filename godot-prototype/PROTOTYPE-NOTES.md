# Prototype notes — Godot pivot test

Built to answer three questions: does the art direction land in 2D, does
the card mechanic feel good, does Godot's workflow sustain.

## Run it

1. Install Godot 4 (4.3+ recommended, GL Compatibility renderer is selected
   in `project.godot`).
2. Open `godot-prototype/project.godot` in Godot. Let the editor process
   the texture imports on first open — the totem PNG and SVGs aren't
   pre-baked. The hero falls back to a flat circle until imports finish;
   restart the scene and the sprite appears.
3. Press **Play** (F5). WASD moves Buffalo. Drag cards from the hand onto
   the sector during prep. Press **Space** to ready up early. Drop a
   Buffalo charge card during the wave to cast a line AoE from Buffalo
   toward the drop point.

## What ships

Spec checklist, all green:

- Buffalo character on screen, WASD-controlled, totem PNG sprite (with
  flat-circle fallback for first-open before imports complete).
- Buffalo sector floor + core in the canonical Buffalo palette, sourced
  from `data/sectors.gd` which mirrors `Sectors.lua` 1:1.
- 5-card hand at the bottom; cards render with faction palette, totem dot,
  cost pip, name, description, flavor.
- Drag-drop unit cards spawn Calf / Ostrich / Longhorn at the drop
  position. Drag-drop building card places (or upgrades) the Production
  Node. Stockpile resource card auto-pays. Charge ability card casts
  during wave from Buffalo toward the drop point.
- Wave timer ticks during prep (30s default). Eight grunts per wave spawn
  off the right edge and walk left toward the core. Units engage on sight.
- Round outcomes: 3 cleared waves → "Run complete." / "We held."; core
  HP 0 → "Run ended." / "The line broke." Single-button restart.
- HUD: Buffalo HP, Core HP, coin balance, phase + round, timer, wave
  banner. All values use design tokens; no hardcoded colors anywhere
  outside `scripts/autoload/design_tokens.gd`.

## What's stubbed or deviated

- **No multiplayer.** Per spec.
- **Totem PNG, not SVG, for Buffalo.** The shipped design system only
  includes `buffalo.png` (the other three are SVG). I kept the asset as
  shipped instead of regenerating an SVG.
- **Hero takes no damage.** Enemies target deployed units or the core,
  never the hero. `Hero.damage()` is plumbed but unused — wire it up if
  you want hero death to count.
- **Adapters consolidated.** The suggested layout listed separate
  `wave_spawner.gd`, `unit_spawner.gd`, `ui_renderer.gd` files; I folded
  them into `scripts/adapters/main.gd` because the wiring is small enough
  that splitting it would just be ceremony. The pure-logic / adapter / data
  split is preserved — the rule that matters.
- **Fonts are Godot's fallback.** The design system specifies Young Serif
  / Nunito / JetBrains Mono. Loading those needs the editor's font
  importer, which is friction I skipped. Numeric values look fine in the
  fallback; type personality is missing.
- **No animations beyond a single tween on the Charge AoE.** Static
  sprites otherwise.
- **No sound.**

## Things to flag for the merge review

- **Card drop targeting is point-based.** The unit goes exactly where you
  drop. With a small sector this can leave units far from the action; we
  may want a "deploy zone" UI cue, or auto-snap toward the core.
- **Charge cast direction is set by drop position relative to the hero.**
  Feels OK with mouse, but it's not a visible aim indicator. A Hades-style
  ghost line during drag would help.
- **The hand spans 5 cards across ~944px.** Fine at 1280×720; a smaller
  viewport would crowd. If we keep this resolution, the gap can grow.
- **Production Node "one per sector" with upgrades on replay.** Plays
  fine as a balance lever but communicates poorly — the second card just
  bumps a tier dot. Worth showing tier-up FX.

## Open questions for the pivot decision

1. The art direction question is half-answered: palette + composition is
   in place, but real illustrations (cards, hero, units) are placeholder.
   Worth committing one illustrated card before judging.
2. The card mechanic prototype demonstrates the loop but doesn't prove
   the *strategy depth*. Three card types and one ability isn't enough to
   tell whether deckbuilding is interesting yet — it tells you whether
   the *interaction* feels good.
3. Architecture discipline carried cleanly. `scripts/logic/*` has zero
   scene-tree references; it ports without changes. If we keep this
   separation, an eventual port back to Roblox or sideways to another
   engine stays cheap.
