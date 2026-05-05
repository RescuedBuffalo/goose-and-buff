# Prototype notes — tile rebuild (canonical)

Architecture-pivot rebuild onto an isometric TileMap. Same wave-defense
loop, same data, same logic. As of this commit the tile rebuild is the
canonical project at the repo root; the previous top-down prototype is
preserved at `archive/godot-top-down/` for reference.

## Run it

Open `project.godot` in Godot 4.6. Click a tile to walk Buffalo. Drag
cards during prep; drop Charge during a wave. Space readies early, Q
casts the signature.

## Ships

16×12 DIAMOND_DOWN grid, 64×32 tiles, procedural atlas (no imported
artwork). Buffalo click-to-move via AStarGrid2D. 15-card Buffalo deck
dealt 5-up. Three waves of grunts pathing to the core. Full
prep / wave / debrief loop, 3-cleared win, core-0 lose, restart. HUD:
HP, Core, coin, phase + round, prep timer.

## Pure-logic changes during the port

**Zero.** `wave_director`, `ability_resolver`, `card_system`, `economy`,
all of `data/*` except `sectors.gd`, and `game_state` ported verbatim.
`sectors.gd` swapped pixel anchors for `Vector2i` tile coords (geometry,
no logic). `design_tokens.gd` lost font / stylebox helpers Phase 1
doesn't use. Layer split survived the engine-shape change.

## Stubbed

Buffalo only — no hero select, no Goose / Fox decks, Snatch no-ops.
Buffalo PNG reused as the tile sprite; other entities are colored
shapes. Hero now takes adjacency damage (top-down flagged it pending).
No tile reservation, no sound, only the Charge-line tween for animation.

## Flag for follow-up

- **Movement feel.** ~0.24 s/tile is snappy but more discrete than the
  free-form top-down motion. Smooth multi-tile tweens may close the gap.
- **Click replan latency.** A new click finishes the in-flight step
  before redirecting. Tween-kill fixes it; deferred.
- **Cardinal-only paths.** Diagonals would smooth follow / chase. One
  flag in `sector._build_astar`.
- **Grid size.** 16×12 fits 1920×1080 but isn't load-bearing. Phase 2
  exploration will want more space; revisit before BUF-128.
- **Re-introducing hero select / Goose + Fox decks.** The data and the
  AbilityResolver branches are preserved verbatim; restoring the select
  flow + extra decks is a copy from `archive/godot-top-down/` plus a
  small adapter scene.
- **Formation control.** Click-to-move invites deliberate movement; the
  next UX question is how the player commands units.

## Comparing against the top-down

`archive/godot-top-down/` holds the v0.1 top-down prototype as it
shipped before the pivot. Run it standalone by opening its
`project.godot`. The data + pure-logic modules in there are 1:1 with
the canonical tree (Phase 1 changed only adapters, scenes, and
`data/sectors.gd`).
