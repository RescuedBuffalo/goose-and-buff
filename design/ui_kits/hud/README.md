# HUD UI Kit

The Heads-Up Display surface. This is what the players see during a run.

**Canonical viewport:** 1280×720 (Roblox renders to 1080p; this is the design size, scale at runtime).

## Layout (anchored to a 24px safe inset)

| Anchor | Component | What it shows |
|---|---|---|
| Top-left, stacked | `HeroBadge` × 3 | Each hero's totem puck, name, HP bar. Order = `Constants.HEROES` (Goose → Buffalo → Fox). |
| Top-right | `WavePill` | Wave number, hero whose turn it is, countdown timer. Backdrop-blur is the **only** blurred surface in the system. |
| Bottom-center | `ValStrip` | The companion's status — where she is, what she's doing, when she's ready. |
| Bottom-left | `AbilityRail` | Q / E / F / R abilities for the local player's hero. Cooldowns shown as bare seconds. |

## Components in this folder

- `HeroBadge.jsx` — totem puck + name + HP bar.
- `WavePill.jsx` — wave banner with backdrop blur.
- `ValStrip.jsx` — companion status pill.
- `AbilityRail.jsx` — Q/E/F/R rail with cooldowns.
- `index.html` — full HUD assembled, with a faux arena behind for context.

## Roblox Studio mapping

The CSS tokens map 1:1 to Color3 values. From `colors_and_type.css`:

```lua
-- Goose totem
local GOOSE_FLOOR = Color3.fromRGB(255, 248, 200)
local GOOSE_CORE  = Color3.fromRGB(252, 222, 40)
-- ...etc; see Sectors.lua (already canonical)
```

For UDim2 padding, use `UDim2.fromOffset(24, 24)` for the safe inset, `UDim2.fromOffset(8, 8)` for hero-badge inner gap, etc — these correspond to `--space-5` and `--space-2`.
