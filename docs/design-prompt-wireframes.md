# Claude Design Prompt — UI Wireframes (Pass 1)

> Paste this into Claude Design as the wireframe brief. Edit anything that doesn't match your gut before sending. Reference the existing design system files in `C:\Users\aidan\Downloads\design\` — the visual identity is locked, this prompt is purely about layout and structure.

---

## Goal

Low-fidelity wireframes for the v0.1 playable surface of **The Long Watch**. Focus on **layout, anchoring, hierarchy, copy** — not pixels. We need to validate flow before committing to detailed mockups.

Output should look like grayscale Balsamiq-style mocks: gray boxes, labeled regions, sketchy hand-drawn-feeling type. No color, no real assets, no animations. The point is to *interrogate the structure* — does the eye know where to go? Is anything missing? Is anything redundant?

## What's already locked (don't redo)

- The full design system (colors, type, motion, voice rules) — see `README.md` and `colors_and_type.css` in the design bundle.
- Three faction palettes (Goose / Buffalo / Fox) and Val's companion palette.
- Voice rules: sentence case, no emoji, hero names in full, HP as `124 / 160`, timers as `0:24`.
- HUD anchoring (per `ui_kits/hud/README.md`):
  - Top-left, stacked: `HeroBadge × 3` (totem + name + HP)
  - Top-right: `WavePill` (wave # + hero whose turn + countdown)
  - Bottom-center: `ValStrip` (companion status)
  - Bottom-left: `AbilityRail` (Q/E/F/R)

## Surfaces to wireframe

### 1. Hero Select Screen (NEW — design from scratch)
The screen a player sees when they join. Three hero cards (Goose, Buffalo, Fox) each showing totem mark, hero name, role label ("Aggression / IGL", "Sentinel anchor", "Initiator / Recon"), short flavor line, and HP/Speed stats. Player clicks a card to lock in. Late joiners see locked cards greyed out and an option to spectate. Show three states: all available, one locked, all locked (spectator-only).

### 2. In-run HUD
Show the assembled HUD over an empty arena. All four anchor regions visible. Add: a **sector core HP indicator** (where? probably above/below the player's own HeroBadge, or floating in-world above the core itself — wireframe both options). Show how the **first-hit player's wave composition panel** appears (modal? side panel? popup near WavePill?) and how **other players see "Fox is in combat" with a coarse health bar** (probably embedded in the HeroBadge for that hero). The info-asymmetry rendering is the spine mechanic — wireframe it carefully.

### 3. Help Request indicator (spine mechanic)
When a teammate presses the help-request hotkey, what shows on the other players' screens? A toast? A pulse on the HeroBadge? A banner near WavePill? Show your strongest pick plus 1-2 alternatives.

### 4. Prep Phase / Build Mode
Between waves, players have ~30 seconds to deploy units in their sector. Wireframe: a deployment palette (Light / Ranged / Heavy unit choices), coin balance, cooldown/cost feedback, "ready up" button to advance. This is **net new** — there's no existing wireframe in the design system.

### 5. Round Transition Screens
- **Prep → wave** transition: countdown into wave, wave-banner shouts ("WAVE 3 — FOX'S TURN")
- **Wave → debrief**: brief score readout, what dropped
- **Run end — victory**: "RUN COMPLETE" + simple stats
- **Run end — defeat**: "RUN ENDED" + which sector fell
- A "return to lobby" or "another run" button on both end screens

## Constraints

- 1280×720 canonical viewport (Roblox renders to 1080p; design at 720p, scale at runtime).
- 24px safe inset from any edge (`--space-5`).
- Center is gameplay — never overlap. HUD lives at the edges.
- Tabular numerals on all numeric data (HP, timers, costs).
- Single ScreenGui per major surface; don't fragment.
- All copy in **sentence case** unless it's a wave-banner shout (ALL-CAPS).

## What I want back

Per surface:
- A grayscale wireframe (annotated)
- A list of the components used (mapped to the existing design system component names where possible — `HeroBadge`, `WavePill`, etc.)
- Open questions where you couldn't decide between two layouts
- A note flagging any moment where the **info-asymmetry mechanic** might leak (e.g., a notification that auto-broadcasts wave composition would break the spine)

## What I do NOT want yet

- Final colors / typography polish
- Specific copy beyond placeholder labels
- Animations / interactions beyond the structural beats
- Component variants (just the canonical state per surface)
- Roblox `ScreenGui` code

That's the next pass.

## Decisions to surface back to me

- Sector core HP: in-world or HUD? (You pick a default but flag the trade-off.)
- First-hit wave composition: modal or sidebar?
- Build/deploy UI: a side rail, a bottom drawer, or a radial menu?
- Should the local player's HeroBadge be visually distinct from teammates'?
