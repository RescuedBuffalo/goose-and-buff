# Prototype notes — survival rebuild

Phase 1 was the wave-defense → cozy-tactical-survival conversion
(BUF-131..138). M2 is the content-depth pass: procgen world, stat
upgrades, biome variety, seed sharing, weapon tiers (BUF-144..149).

## Run it

Open `project.godot` in Godot 4.6. The boot scene is the run-start
screen — pick a totem, optionally paste a watch seed, click Start.
WASD walks the hero. Cursor sets facing. Left-click swings (or fires
arrows when a bow is equipped). Hold E to gather. 1..8 selects an
inventory slot; right-click clears the build preview. F3 toggles the
chunk debug overlay; F4 dumps the current WorldDef to `user://debug/`.

## Ships in M2

- **Procgen world (BUF-144)** — `scripts/logic/world_generator.gd`
  stamps 14 chunk templates (5×5 tiles each) onto a 5×5 chunk grid.
  Lodge plaza fixed at the center; spawn road across the south. Same
  seed → same world. Generation completes in <10 ms.
- **Stat upgrades (BUF-147)** — `data/upgrades.gd` + `scripts/logic/
  stat_system.gd`. 24 upgrades across Buffalo / Goose / Fox / Shared
  tabs, three tiers deep with prereqs. Flat-then-percent composition.
  Caching: `effective_stats` recomputes only when owned set changes.
- **Seed sharing + debug (BUF-145)** — run-start screen takes an
  optional watch seed (8-char hex). Run-end screen shows the seed +
  Copy button. F3 overlay highlights chunk borders + climate; F4 dumps
  the WorldDef.
- **Lodge tree UI (BUF-148)** — per-hero tabs, owned/available/locked
  states distinct, prereq lines drawn dashed. "Light this ember?"
  confirm dialog before spending.
- **Upgrade pool + weapons (BUF-149)** — iron axe, steel axe, long
  spear, hunter's bow + arrows. Bow ranged combat: projectile path,
  ammo from inventory, single new branch in the swing resolver. Earn
  rate produces ~5–10 embers per typical run via `data/run_economy.gd`.
- **Biome variety + cold deepening (BUF-146)** — three climate variants
  (temperate / frosted / frozen) at gen-time; canvas modulate adds an
  ice-blue overlay that strengthens across days 1→3. Day banners use
  the locked seasonal language ("Day 2 — the long cold, gather and
  prepare").

## Calls I made on my own

- **World generates ONCE per run on day-1 weights.** The brief gave
  three per-day distributions; per-day regen would wipe placed walls
  and gathered resources mid-run. Instead, the world has day-1
  variety and the lighting adapter ramps cold-tint each successive
  night. Per-day chunk regen is a parking-lot for M3 if the visual
  shift doesn't land.
- **Chunk borders are walkable by design.** No T/R/W on the outer
  ring of any non-center chunk. AStar reachability from spawn to lodge
  is therefore guaranteed without a validate-and-retry loop.
- **`inventory_slots` is wired end-to-end.** `InventorySystem.slot_count`
  is mutable via `set_slot_count()`; main applies the upgrade before
  reset; the HUD reads the live count and widens the strip. Slots 9+
  are storage-only (only hotbar_1..hotbar_8 are registered actions).
- **First-pass ember earn rates.** 6 victory + 1 per night survived on
  defeat + small stretch bonuses. Real numbers need playtest data.
- **Climate cold-tint amounts** (lighting_adapter.gd) are picked by
  eye, not from design tokens. Real values when art lands.

## Open questions for Aidan

- **Ember earn curve.** Are 5–10 embers/run the right pace, or should
  victory feel more rewarding to push harder builds?
- **Per-day chunk regen vs. overlay.** The overlay reads cold-deepening
  cleanly; if you want sharper biome shift between days, regen is the
  honest answer.
- **Bow + spear balance.** Ranged is generous (14 px hit radius).
  Tighten on playtest.
- **Goose/Fox ability cooldown stat is wired into effective_stats but
  no abilities are bound yet** — once Q-bound abilities ship, the
  cooldown stat will land.

## 2-minute playtest impression

The run-start screen lands the seasonal frame immediately — picking a
totem and committing a watch seed feels like a decision. The procgen
world reads as varied without being chaotic; chunks are large enough
that the player builds spatial memory inside a single run. The stat
tree is short but legible; spending the first ember is a clear
moment ("more HP this watch"). Bow ranged combat changes the pace —
holding a tile against wolves now has both reach and melee shapes.

The cold-deepening across days reads on a quick comparison (day 1 vs
day 3), but in flow the shift is subtle. Real biome tile art will do
more of the work than the canvas tint alone.

## Stubbed / out of MVP scope

- 3-player multiplayer, real biome tile art, real upgrade icons,
  sorcerer-demon enemies, exploration / fog-of-war, weather, respec,
  achievements, daily seed challenges, server telemetry, sound.
- Hero abilities (Q-bound charge / dive / snatch). The cooldown stat
  is plumbed via `GameState.signature_cooldown_max`; wiring is
  BUF-150-ish.
