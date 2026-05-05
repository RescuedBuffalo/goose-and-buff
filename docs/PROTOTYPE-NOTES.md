# Prototype notes — survival rebuild

Phase 1 conversion from wave-defense to cozy-tactical survival on the
isometric tile grid (Linear: BUF-131..BUF-138). Same engine, same data
layer, same architecture rules. Card hand and phase button are gone;
day/night, gather, build, and a hand-grain combat swing replace them.

## Run it

Open `project.godot` in Godot 4.6. WASD walks the hero. Cursor sets
facing. Left-click swings the equipped weapon (or places a placeable
when one is selected). Hold E next to a tree / rock / bush to gather.
1..8 selects an inventory slot; right-click clears the build preview.

## Ships

- **Day/night cycle** — DAY 60s / DUSK 5s / NIGHT 30s / DAWN 5s, 3
  nights to victory. Lighting tints world via CanvasModulate.
- **Inventory** — 8 slots + equipped slot. Stack semantics, hotkeys.
- **Combat** — cone-arc swing, weapons table, cooldowns, damage flash.
- **Gather** — hold-E pulls trees/rocks/bushes into inventory at
  tool-affinity rate. Hand axe = 3x wood; bare hands = 1x base.
- **Build** — ghost preview, recipe deduct, AStar update on place.
- **World** — 25x25 hand-crafted: lodge core center, treeline north,
  rocks east, water west, berries + open ground south. Wolves spawn
  at the south edge during night, path to the lodge.
- **HUD restyle** — top band: hero HP, lodge HP, "Day N — gather and
  prepare" / "Night N — hold the line", phase countdown. Bottom band:
  inventory grid + equipped slot. End screens show stats.

## Pure-logic changes during the conversion

`wave_director.gd` was the load-bearing edit. The PREP / DEBRIEF
internal timers and auto-round-advance logic were removed; new
`start_wave(round)` / `end_wave()` entry points let DayNightCycle
drive transitions externally. Spawn-queue mechanics and the
composition data are unchanged. `card_system.gd`, `economy.gd`,
`ability_resolver.gd` all preserved verbatim — dormant in MVP.

## Stubbed / out of MVP scope

- Wolves don't attack walls (path around them). Walls function as
  reroutes only. Hero abilities (Q-bound Charge / Dive / Snatch) not
  wired — `AbilityResolver` intact for the follow-up.
- Coin economy + production node still in code; HUD doesn't surface
  coins anymore (demoted per brief).
- Inventory overflow drops to a `push_warning`, not a world pickup.
- Owl + bear archetypes designed in `data/enemies.gd` (Bruiser etc)
  but only `FrostWolf` ships in waves.

## Design calls I made on my own

- WASD walks **screen-cardinal** (Hades / Stardew). Iso tile-axis
  movement felt squirrelly in playtest — straight-up screen up matches
  player intuition. Tile coords update as the hero crosses boundaries.
- Hero faces **the cursor at all times** (cleanest read for the swing
  arc). Last-movement-direction fallback was dropped — the cursor
  always provides a vector unless it's literally on the hero.
- Hero death **ends the run**. No respawn / down state. Survival MVP
  needs the stakes to land.
- Starter inventory: hand axe (slot 0) + 4 walls (slot 1). Lets day 1
  feel productive without a tool-discovery loop.

## Open questions for Aidan

- **What does the lodge core do besides die at HP 0?** Passive
  production? Heal aura? Currently inert except as a damage target.
- **Wave intensity scaling.** Night 1 = 6 wolves @ 2.5s, Night 3 = 12
  @ 1.6s. First-pass guess; needs a real playtest pass.
- **Pickup-on-floor for inventory overflow.** Brief says drop a
  `world_pickup`; deferred to a follow-up — currently logs and drops.
- **Wolves vs walls.** Walls reroute; should they also take damage?
  If yes, walls become a real economy of wood, not a one-time pour.

## 30-second playtest impression

It reads as survival, not wave-defense in a tile costume. Walking
into the world to find trees, watching the light shift toward dusk,
hearing the night start — those are different shapes than "press
button to begin wave." The lodge-center framing is doing real work.

What's still wave-defense-shaped: the lodge HP bar dominates as the
primary failure state, and night raids feel like waves more than
ambient threats. Whether that becomes "survival" or stays "tile
wave-defense" depends on what M2 layers on — variable threats, hero
abilities, lodge upgrades. The shape now supports either.
