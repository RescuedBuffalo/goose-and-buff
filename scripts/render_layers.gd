class_name RenderLayers
extends Object
##
## Single source of truth for z_index values across the world canvas.
##
## ─────────────────────────────────────────────────────────────────────────
## The full stack, front-to-back (lower z = behind, higher z = in front):
##
##   HUD                  CanvasLayer (separate)  HP chip, lobby, end screen
##   PLACEMENT_PREVIEW    z = 90                  Build ghosts, mouseover highlights
##   LIGHTING_OVERLAY     z = 80                  Day/night tint, weather particles
##   WORLD_LABELS         z = 6                   Damage numbers, floating text
##   WORLD_VFX            z = 4                   Swing arcs, hit splashes, ability casts
##   WORLD_ENTITIES       z = 0  (Y-SORTED)       Characters, enemies, trees, lodge,
##                                                projectiles, resource nodes, placeables
##   CHARACTER_SHADOW     z = -10                 Procedural ellipse under each character
##   GROUND_DECALS        z = -50                 Future: footprints, blood pools, scorch
##   GROUND_BASE          z = -100                TileMapLayer — grass/water/lodge floor
##
## ─────────────────────────────────────────────────────────────────────────
## RULES OF THUMB when adding new content:
##
## 1. If it's "in the world" and characters can stand behind/in-front of it
##    visually, it goes at WORLD_ENTITIES (z=0). Y-sort handles occlusion.
##    This is true for trees, the lodge, placeables, projectiles, enemies,
##    heroes, resource nodes — anything that has a footprint on the ground.
##
## 2. If it's drawn ON the character (a jacket, a hat, an animated weapon
##    in M4), it's NOT a separate z layer. It's a bone child inside the
##    character's Skeleton2D rig. Bone hierarchy + scene order handles its
##    layering relative to the character's other body parts.
##
## 3. If it's drawn ON the ground but moves with a character (shadow), it's
##    CHARACTER_SHADOW (z=-10) with z_as_relative=false so it stays pinned
##    to the absolute ground layer regardless of its parent's z.
##
## 4. If it's drawn ABOVE the world but below UI (a swing-arc VFX, a damage
##    number, a build-placement ghost), pick the matching world-overlay
##    layer (4, 6, 90 respectively). These don't Y-sort — they always render
##    above all WORLD_ENTITIES regardless of position. This is intentional:
##    a swing arc behind a tree is harder to read than one always visible.
##
## 5. If it's truly screen-space (HUD, menus, end-screen), use a separate
##    CanvasLayer entirely (see main.gd). z_index doesn't apply across
##    CanvasLayers — they layer by their own .layer property.
##
## ─────────────────────────────────────────────────────────────────────────
## INVARIANTS to preserve:
##
##   GROUND_BASE        < CHARACTER_SHADOW
##   CHARACTER_SHADOW   < WORLD_ENTITIES
##   WORLD_ENTITIES     < WORLD_VFX
##   WORLD_VFX          < WORLD_LABELS
##   WORLD_LABELS       < LIGHTING_OVERLAY
##   LIGHTING_OVERLAY   < PLACEMENT_PREVIEW
##
## Each layer leaves headroom (40+ units to neighbors) so we can slot a
## new sublayer in without renumbering everything else.

# ── Ground (below characters) ─────────────────────────────────────────────
const GROUND_BASE := -100
const GROUND_DECALS := -50
const CHARACTER_SHADOW := -10

# ── World entities (default Y-sort group) ────────────────────────────────
const WORLD_ENTITIES := 0

# ── World overlays (above entities, below HUD) ───────────────────────────
const WORLD_VFX := 4
const WORLD_LABELS := 6
const LIGHTING_OVERLAY := 80
const PLACEMENT_PREVIEW := 90
