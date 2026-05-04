# Character Briefs UI Kit

Blender-prompt-ready briefs for the four canonical characters: **Goose**, **Buffalo**, **Fox**, and **Val** (the Australian Shepherd companion).

## What's here

- `index.html` — all four briefs on one page, parchment-toned, designed for printing or pasting into a Discord thread for the friends.
- `Brief.jsx` — single-character brief component. Reusable.
- `BlenderPrompt.jsx` — the prompt-template card.

## How to use

Each brief contains: palette, stats (HP / speed from `Heroes.lua`), silhouette description, proportion exaggeration, texture notes, and a one-line "vibe" callout in the hero's accent color.

The Blender prompt at the bottom is a template — copy it, fill in the bracketed subject, and feed it to your modeler (or AI 3D tool). Output target is GLB with vertex colors only, ~600–1200 polys, Roblox-import-ready.

## Stats source of truth

Stats come directly from `src/shared/Data/Heroes.lua`:

```lua
Goose   = { baseHealth = 100, moveSpeed = 18 }
Buffalo = { baseHealth = 160, moveSpeed = 12 }
Fox     = { baseHealth = 85,  moveSpeed = 22 }
```

Val has no stats yet — companion logic is unspecified in the v0.1 prototype. The brief flags this explicitly. (Val is a he — modeled on the author's actual Aussie.)
