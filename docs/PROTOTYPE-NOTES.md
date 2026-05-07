# Prototype notes — survival rebuild

Phase 1 was the wave-defense → cozy-tactical-survival conversion
(BUF-131..138). M2 is the content-depth pass: procgen world, stat
upgrades, biome variety, seed sharing, weapon tiers (BUF-144..149).

## Run it

Open `project.godot` in Godot 4.6. The boot scene is the run-start
screen — pick a totem, optionally paste a watch seed, then either
"Stand the watch alone" (solo) or "Stand it with friends"
(multiplayer lobby). WASD walks the hero. Cursor sets facing.
Left-click swings (or fires arrows when a bow is equipped). **F is
gather** (moved off E in M4 — see BUF-154). **E held + click on a
teammate / portrait** fires the help ability. **Q** fires the hero's
signature ability (Charge / Dive / Snatch). **R held** revives a
fallen friend within one tile. 1..8 selects an inventory slot;
right-click clears the build preview. F3 toggles the chunk debug
overlay; F4 dumps the current WorldDef to `user://debug/`.

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

## Ships in M4 (BUF-150..155)

- **Multiplayer foundation (BUF-150)** — `scripts/adapters/multiplayer_io.gd`
  autoload owns the MultiplayerAPI lifecycle. Lobby scene at
  `scenes/ui/lobby.tscn`. Host generates a 6-char code from a 31-char
  alphabet (no 0/O/1/I/L for voice survival). Join takes a host
  address + code; ENet direct on port 55432. Hero-select syncs across
  peers via RPC; locked-out duplicates. "Light the lantern" broadcasts
  run-start.
- **World + hero replication (BUF-151)** — `scripts/adapters/replication.gd`
  is the only place RPCs live for the gameplay scene. Determinism
  guarantee: the host broadcasts its run seed; clients regenerate the
  procgen world locally. WaveDirector got `set_seed` so round-2 archetype
  rolls match across peers. Hero positions sync at 10Hz via host relay.
  Each peer drives input for its local hero; remote heroes are puppets.
- **Combat + downed/revive (BUF-152)** — Client swing → host resolves
  via a per-call CombatSystem → broadcasts damage. Q-bound signatures
  (Charge / Dive / Snatch) wired through AbilityResolver.resolve and
  the new `_apply_signature_effect` dispatch. 0 HP → kneel + 30s timer
  ring. Teammate within 1 tile holds R for 3s → revive at 25% HP.
  Timer expires → fallen state. Visual ring shows both timers above
  the hero.
- **Sequential info-asymmetric waves (BUF-153)** — the spine. Host
  picks first-hit hero per wave with a rotating front (north → east
  → south) plus a hero-default-front bias from
  `data/multiplayer.gd.HERO_FRONT_DEFAULT`. Veil discipline: the wave
  banner reads "the cold comes from the &lt;direction&gt;" only for the
  first-hit hero; non-first-hit teammates see only "Goose is in
  combat. Listen for the call." Veil lifts when a teammate walks
  within 6 tiles of any wave enemy.
- **Cross-sector help abilities (BUF-154)** — `AbilityResolver.resolve_help`
  produces effect dicts for `BuffaloStampede` (line charge),
  `GooseCover` (buff zone), `FoxSteal` (mark + double damage). E held
  + click teammate / portrait, OR double-tap E to quick-target the
  most-in-combat teammate. 25s cooldown.
- **Connection state copy + AI placeholder (BUF-155)** —
  `data/multiplayer.gd.connection_copy()` maps state ids to seasonal-
  frame strings. HUD shows the banner for ~3.5s on transition. AI
  placeholder = freeze-in-place + "AI" badge under the totem on
  disconnect. Host drop returns everyone to the lobby.

## Calls I made during the M4 pass

- **Help-ability cooldown 25s** (mid of the 20-30 spec). Tune after
  first 3-player playtest — multiple help moments per wave may want 20.
- **Veil lift = 6 tiles of LOS** (eyeballed). Playtest may want 4 or 8.
- **Position sync at 10Hz** — local hero feels zero-lag from its own
  input prediction; remote heroes snap at 100ms intervals. Can bump
  to 20Hz if motion reads jittery.
- **AI placeholder = freeze + badge.** Auto-attack-in-radius is M5
  polish; currently the dropped hero just stands there. Voice still
  carries during the 10s reconnect window.
- **Sectors-as-fronts** (the brief's default). Flagged below for Aidan.
- **Gather key moved E → F.** BUF-154 explicitly binds E to help; the
  cleanest resolution. Hint label updated.

## Open questions for Aidan (M4)

- **Sectors-as-fronts vs. spatially-separated regions.** The current
  build treats the world as one shared space with a rotating front
  for first-hit calculation. After the first 3-player playtest: does
  the rotating front read as enough sector-identity, or do players
  treat the world as undifferentiated and the "front" abstraction
  doesn't land?
- **Help-ability cooldown** — 25s plays well solo; in a real wave
  with three help moments back-to-back, 20s might land better.
- **Reconnect flow.** v1 is "drop → AI placeholder → either reconnect
  in 10s or fallen for the run". Mid-run rejoin is parking-lot per
  the brief; flag for M5 if drops happen often during playtest.

## Stubbed / out of M4 scope (M5+)

- **Help effect mechanics.** Cover's buff zone and Steal's yank are
  cast-and-broadcast as visuals but the actual buff (attack-speed,
  damage-resist, position pull) isn't wired into combat. Stampede
  damage works; the others are visual flashes for now.
- **AI placeholder auto-attack.** Dropped heroes stand still; M5
  wires basic auto-attack-in-radius.
- **Host-arbitrated pickups + buildings.** Each peer's gather and
  build flow runs locally without host reconciliation. Potential
  desync if two players grab the same node simultaneously — flagged
  but not exercised in solo.
- **Per-peer combat stat modifiers in MP.** Host's `host_resolve_remote_swing`
  uses default 1.0 multipliers when running combat for a remote peer
  (their own lodge upgrades don't propagate to host). Solo combat is
  unaffected.
- **Floating damage numbers on clients** for melee hits — bound to
  the local CombatSystem's signal which doesn't fire from RPC damage
  application paths. Visual polish only.
- **Dawn respawn for fallen heroes.** Fallen state is rendered; the
  next-dawn respawn at 25% HP isn't yet hooked to `_on_phase_changed`.
- **Real biome tile art**, sound effects for new states, sorcerer-
  demon enemies, exploration / fog-of-war, weather, respec, daily
  seed challenges, server-side telemetry — all unchanged from M3
  parking-lot.

## 3-player playtest impression

I have not been able to run a 3-machine playtest from this worktree
— the spine mechanic's actual feel needs three humans on three
laptops. Solo path runs clean (M2 single-player is unchanged). The
honest limit: until Aidan, Goose, and Beau actually play through the
integration narrative, the "voice-comms-IS-gameplay" pillar lands
or it doesn't. The visible scaffolding is in place; the playtest is
the verdict.

## Ships in BUF-156 (Q-bound signature abilities)

Q now fires the equipped hero's signature ability end-to-end:

- **Charge / Dive / Snatch all resolve.** `data/cards.gd` was missing
  `card.dive` and `card.snatch` payloads; the resolver was crashing on
  those branches. Added both with v1 numbers (Dive: 240 px cone, 30°
  half-angle, 35 dmg; Snatch: 280 px max dash, 56 px strike radius, 40
  dmg, 2× backstab). `AbilityResolver.resolve()` is unchanged — it
  already had the dispatch shape.
- **Cooldown HUD chip.** `scripts/ui/hud_widget.gd` draws a third chip
  between LODGE and the centered headline. Sentence-case "Q — Charge /
  Dive / Snatch" label, "Ready" or `0:04` value (voice rule), thin rail
  underneath that fills as the cooldown drains. All colors come from
  `DesignTokens` — `PARCHMENT_0` for ready, `FG_3` for muted.
- **Telemetry contract.** `ability_cast` events now carry
  `hero_id, ability_id, day_index, phase, caster_peer`. The router
  reads day_index + phase via a `day_night_provider` Callable so the
  resolver itself stays scene-tree-free (BUF-156 acceptance #4).
- **Wiring test.** `scripts/tests/ability_resolver_test.gd` runs four
  cases on F12 — one per ability plus the unknown-id fallback. Locks
  in the cards.gd → resolver contract so a missing payload won't go
  silent again.

## Calls I made on my own (BUF-156)

- **Dive / Snatch tuning numbers** — picked by analogy with Charge.
  Snatch hits hardest single-target (40) because its cone is small and
  its range cap is generous; Dive's 35 sits between Charge's 30 and
  Snatch's 40 to differentiate the cone from the line. Tune after the
  first 3-hero playtest.
- **Chip placement** at `pad + 480` between the lodge and the centered
  headline. Left-to-right scan reads HERO → LODGE → Q ABILITY → phase
  → timer, which matches the priority order during a wave.
- **No SFX hook.** Per the issue's out-of-scope list — sound for casts
  is M3. The visual flash from `combat_visuals` is the only feedback.
- **Buffalo ability label trimmed to "Charge"** so the chip reads
  parallel across heroes ("Q — Charge / Dive / Snatch"). Heroes data
  still calls it "Buffalo charge" everywhere else.

## Open questions for Aidan (BUF-156)

- **Dive / Snatch damage curves** — the 30/35/40 ladder is a guess.
  Snatch in particular wants playtest data on how often the dash lands
  *behind* enemies (backstab x2 makes it the highest theoretical
  burst, but only when the geometry cooperates).
- **Cooldown rail visibility** — at 1080p the chip reads cleanly, but
  on a smaller display the Q chip + LODGE chip + headline sit close.
  If the headline gets crowded, drop the rail width from 160 → 120.
