# Claude Design Prompt — Detailed UI Implementation (Pass 2)

> Run this only AFTER the wireframe pass has been reviewed and the open questions resolved. This pass produces production-ready UI mockups + Roblox-Studio-ready specs.

---

## Goal

High-fidelity implementation of every surface signed off in the wireframe pass. Output should be **Figma frames + handoff specs** that I can mirror 1:1 in Roblox Studio. Every component must reference design tokens by name (no hex codes, no font sizes outside the scale).

This pass is where the design system *meets the engine*. Anything ambiguous here costs us in implementation later.

## What's already locked

- Design system tokens in `colors_and_type.css` and the Roblox `DesignTokens` ModuleScript.
- Wireframe layout (from Pass 1), including all open-question resolutions.
- Voice rules (sentence case, no emoji, full hero names, tabular HP / timers).
- HUD anchoring (top-left HeroBadges, top-right WavePill, bottom-center ValStrip, bottom-left AbilityRail).

## Surfaces to implement at fidelity

For each, deliver: full mockup, all component variants (default / hover / active / disabled / loading / error states where applicable), and a Roblox-spec handoff sheet (see "Handoff format" below).

1. **Hero Select Screen** (with all three states from the wireframe)
2. **In-run HUD** (with sector core HP, info-asymmetry views, help-request indicator)
3. **Prep Phase / Build Mode** (deployment palette, coin balance, ready-up)
4. **Round Transition screens** (countdown, wave banner, debrief, victory, defeat)
5. **The four HUD components individually**, in isolation, ready for component library: `HeroBadge`, `WavePill`, `ValStrip`, `AbilityRail`
6. **Sector core HP indicator** in both options if the wireframe didn't fully commit (in-world float vs HUD-anchored)
7. **Help-request toast / indicator** at full fidelity

## Handoff format (per component)

Every component gets a handoff sheet structured as:

```
Component: HeroBadge
Anchor: top-left, stacked. Inset 24px.
Size: 280 × 64 (default). 280 × 56 (compact).
States: default | self | offline | downed | speaking
Tokens used:
  - Background: --bg-card (Night[1])
  - Border: --hairline-warm
  - Hero accent (left edge): DesignTokens.Hero[heroId].core
  - HP fill: --hp-full / --hp-warn / --hp-crit (state-dependent)
  - Text primary: --fg-1
  - Text secondary: --fg-2
  - Padding: --space-3 (12px) horizontal, --space-2 (8px) vertical
  - Inner gap: --space-2 (8px) between totem and label stack
  - Radius: --radius-3 (14px)
  - Shadow: --shadow-2
  - Tween (state change): DesignTokens.Tween.out, 0.22s
Roblox primitives:
  - Frame (root) with UICorner + UIStroke + UIPadding + UIListLayout
  - ImageLabel (totem)
  - TextLabel (hero name, --font-display 20px)
  - TextLabel (HP, --font-mono tabular-nums 16px)
  - Frame (HP bar) with two stacked sub-Frames for fill / track
Behavior:
  - HP changes animate fill width over 220ms with Tween.out
  - State change to "downed" applies opacity 0.4 (per design rules)
Edge cases:
  - When name is too long, truncate with ellipsis at 14ch
  - When core HP is below 25%, the badge pulses subtly (1px translateY at 1Hz)
  - "speaking" state adds a soft outer glow in hero core color
```

That's the level of detail we need for every component.

## Constraints (same as Pass 1, restated for safety)

- All colors must come from `DesignTokens` (Roblox) / `colors_and_type.css` (CSS). Never hardcode.
- All sizes from the spacing scale (`--space-1` through `--space-9`). No arbitrary px values.
- All text from the type scale (`--fs-xs` through `--fs-display`). Floor for HUD: 18px @ 1080p (per design system README).
- All radii from the radius scale (`--radius-1` through `--radius-4`).
- All easing/durations from the motion scale (`--ease-out`, `--ease-pounce`, `--ease-buffalo`; `--dur-fast/base/slow`).
- No emoji.
- Sentence case on UI; ALL-CAPS only for eyebrow labels and wave-banner shouts.
- Backdrop blur is allowed in **one** place: behind the WavePill. Nowhere else.
- Tabular numerals on every number that changes during play (HP, timers, costs, coin).
- Reduced-motion fallback: collapse all transforms to opacity fades.

## Godot primitives lookup (for translation)

When you write Godot-spec handoff sheets, use this mapping:

| Design concept | Godot primitive |
|---|---|
| `<div>` container | `Control` or `PanelContainer` |
| Card (rounded, shadowed) | `PanelContainer` with `StyleBoxFlat` (corner_radius + bg_color + border + shadow) |
| Text | `Label` (or `RichTextLabel` for inline formatting) |
| Image (totem, icon) | `TextureRect` |
| Button | `Button` (or `TextureButton` for icon-only) |
| Bar / progress | `ProgressBar` (or `TextureProgressBar` for custom fill art) |
| Vertical/horizontal stack | `VBoxContainer` / `HBoxContainer` |
| Padding | `MarginContainer` |
| Gradient | `GradientTexture2D` on a `TextureRect`, or paint via `_draw()` |
| Pill / fully rounded | `StyleBoxFlat` with `corner_radius` set to half of the height |
| `gap` between siblings | `BoxContainer.add_theme_constant_override("separation", value)` |

Theme is the canonical place to apply design tokens. Build a `Theme` resource that sets the default fonts, font sizes, and `StyleBoxFlat` for each Control variant; reference it from the root scene so all descendants inherit. Variants (e.g., a card-tier StyleBox vs a HUD-panel StyleBox) live as named theme variations.

Backdrop blur on the WavePill: use a `Control` with a `ShaderMaterial` running a Gaussian-blur shader on the screen buffer (Godot 4 supports this via `BackBufferCopy` + `screen_texture`). It's slightly fiddly but native, no edge-case workaround needed.

## What I want back

- One Figma file per surface (or one large file with surfaces as pages)
- A separate component-library page with the four named HUD components in isolation
- A handoff sheet per component (per the format above)
- A migration note for any token I should add to `DesignTokens.lua` if your design uses something not yet in the system (every addition needs a CSS counterpart too)

## What I do NOT want

- Roblox `ScreenGui` code (I'll write that against your handoff sheets)
- Animation rigs (handled separately in Blender)
- Real character renders / asset PNGs (those come from Blender; use the totem SVGs from the design bundle as placeholders)
- Any decision that contradicts the wireframe sign-off — if you find one that should change, surface it as an Open Question, don't quietly diverge

## Decisions to surface back to me

- Anywhere a token is missing from the design system and you had to invent one
- Any place where Roblox's primitive set genuinely can't render the design (e.g., curved gradients along arbitrary paths)
- Any animation/interaction you'd prototype in Figma but can't replicate in Roblox cleanly
- Any place where the floor sizes (14px UI / 18px HUD) constrained what you wanted to do
