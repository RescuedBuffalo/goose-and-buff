# The Long Watch — Design System

> Cozy-but-tactical visual language for **The Long Watch** — a private 3-player co-op Roblox roguelite. Three animal-totem heroes (Goose, Buffalo, Fox) defend their cores alongside Val, the shared Australian Shepherd companion. The title evokes the wave-defense rhythm: the lights are low, the friends are at their posts, the watch is long.

This system is deliberately small and opinionated. Audience is three real friends, not a public release — design for **personality and legibility**, not virality.

---

## What's here

| File / Folder | What it's for |
|---|---|
| `README.md` | This file. Brand overview, content/visual foundations, iconography. |
| `SKILL.md` | Agent skill manifest. Drop this folder into Claude Code as a skill. |
| `colors_and_type.css` | Source-of-truth tokens — colors (hero totems, neutrals, semantic), type, spacing, radii, shadows, motion. |
| `fonts/` | Webfonts (currently CDN'd via Google Fonts; flagged below for replacement). |
| `src/` | The Roblox v0.1 prototype source (Lua). Imported from `RescuedBuffalo/goose-and-buff` for reference. |
| `preview/` | HTML cards that populate the Design System tab. Don't ship; they're documentation. |
| `ui_kits/hud/` | Roblox Studio-ready HUD spec — health, core, wave banner, hero badge. |
| `ui_kits/character_briefs/` | Blender-prompt-ready character briefs (Goose, Buffalo, Fox, Val). |
| `assets/` | Logos, totem marks, illustrations. |

---

## Sources

- **GitHub:** [`RescuedBuffalo/goose-and-buff`](https://github.com/RescuedBuffalo/goose-and-buff) — v0.1 Roblox prototype. Lua source imported into `src/`. Files of note:
  - `src/shared/Data/Heroes.lua` — base stats per hero (canonical HP/speed values).
  - `src/shared/Data/Sectors.lua` — **canonical color palette** (RGB values copied verbatim into `colors_and_type.css`).
  - `src/shared/Shared/Constants.lua` — hero order, max players (3).
  - `src/server/Adapters/WorldBuilder.lua` — arena layout (cores, spawn pads, dividers).
  - `src/server/Systems/WaveDirector.lua` — round 1 schedule (Fox @ 0s, Goose @ 12s, Buffalo @ 24s).
- **Visual mood:** Spiritfarer (warmth, color), Hades (clarity, character-forward UI), A Hat in Time (chunky stylization, animal personality), Wytchwood (dark-but-cozy palettes).
- **No Figma file exists yet.** Visual foundations below extrapolate from the Lua color tokens + brief.

---

## CONTENT FUNDAMENTALS

The voice is the **inside-joke book club**, not the marketing deck. Warm, opinionated, playful but never ironic. Three friends written for, by one of them.

**Who's speaking, who's spoken to.**
- Default voice is **second-person, warm**: "you brought Goose tonight."
- The game itself can speak in **first-person plural** for moments of solidarity: "we held the line."
- Hero callouts are short and in-character — Buffalo grunts, Goose honks (literally), Fox hums. Never long monologues.

**Casing.**
- Sentence case for everything UI: buttons, headers, labels. ("Start a run", not "START A RUN" or "Start A Run".)
- Display headlines may use Title Case sparingly when they're a *name* of something: "The Long Honk", "Three Animals, One Den".
- ALL-CAPS only for short eyebrow labels and wave-banner shouts ("WAVE 3 — FOX'S TURN").

**Tone examples.**
- ✅ "Goose is down. Val's circling — give him a sec."
- ✅ "Buffalo's core is at half. Pulling back to regroup."
- ✅ "Wave 4 incoming. Fox, you're on point."
- ❌ "Player 1 has been eliminated." *(too clinical)*
- ❌ "EPIC WAVE INCOMING!!! 🔥🔥🔥" *(too try-hard, too marketing)*
- ❌ "Skill issue lol" *(ironic — we don't do ironic)*

**Inside-jokes.**
- Welcome where they don't break legibility. The wave banner can say "Goose hour" when it's Goose's wave and you're between friends; never on a tutorial screen.
- A small allowance: hero names are **always** the canonical names (Goose, Buffalo, Fox). Don't shorten to "G", "Buf", "F" in UI — those are Discord, not the game.

**Emoji & punctuation.**
- **No emoji in UI.** Period. The animal totems are the emoji.
- Em dashes are fine — they match the conversational cadence.
- Single exclamation for emphasis. Never two. Never three.
- Ellipsis only when the speaker is genuinely trailing off ("Val's still circling…").

**Numbers & data.**
- Use **tabular numerals** for HP, timers, wave counts. (`font-variant-numeric: tabular-nums` is on `.numeric`.)
- HP shown as `124 / 160`, never `124/160` or `124-160`.
- Timers as `0:24`, never `24s` (small visual difference, big legibility win at 4K Roblox renders).

---

## VISUAL FOUNDATIONS

The look is **dark-but-cozy with totem-warm accents**. Wytchwood night palette as ground; Spiritfarer-warm hero colors as wayfinding; Hades-clear typography on top.

**Color.**
- Three hero "totems" anchor everything: **Goose = cream + sun-yellow**, **Buffalo = warm earth + deep umber**, **Fox = peach amber + burnt orange**. RGB values are copied verbatim from `Sectors.lua` so the in-Roblox arena and the UI agree pixel-for-pixel.
- Neutrals are **night** (deep dusk to muted ink) and **parchment** (warm cream to charred earth). Never use pure black, never pure white. The system has no greys — only warm-leaning or cool-leaning neutrals.
- Semantic colors (HP, shield, XP, gold) are **named after the world**, not the function: `--hp-full` is "mossy green", `--core-shield` is "glacier blue", `--xp-glow` is "twilight violet".
- Val's palette (merle slate, belly cream, rust tan) is reserved for the companion — never apply Val colors to a hero surface or vice versa.

**Type.**
- Display: **Young Serif** — chunky, slab-ish old-style serif. Warm, readable, not Fraunces. Used for hero names, run titles, big numbers.
- Body: **Nunito** — humanist sans with rounded terminals. Legible at Roblox's 1080p HUD distances.
- Mono: **JetBrains Mono** — for HP counters, run seeds, debug overlays.
- **Floor sizes:** UI never goes below 14px. Roblox HUD never below 18px (rendered to 1080p). Wave banner shouts at 64–88px.

**Spacing & rhythm.**
- 4px grid. Use the named tokens (`--space-1` … `--space-9`) not raw pixels.
- HUD elements respect a **safe inset of 24px** (`--space-5`) from any screen edge.
- Cards stack with `gap: var(--space-4)` by default — never margins on siblings.

**Backgrounds.**
- App background is **`--night-0`** (deep dusk). Never gradients across the whole screen — gradients are reserved for hero-totem **inner glow** on cards.
- A single subtle **vignette** is allowed on full-bleed scenes (Roblox menu, character select).
- Patterns/textures are **not** used in v0.1. Color blocks beat textures (this is also called out as a constraint in `Sectors.lua`'s comments — we honor it in UI too).
- Full-bleed imagery is reserved for the title screen and cutscene cards.

**Cards.**
- Default card: `--bg-card` (`--night-1`), `--radius-3` (14px), `--hairline` border, `--shadow-2` drop, plus `--inset-warm` inner highlight on the top edge. The inner highlight is the cozy signature — it makes the card feel lit by an unseen lantern.
- Hero-themed cards swap the inner highlight for the hero's `--core` color at low alpha, and add a 1px hero-tinted top border. Never tint the whole card — only the lantern strip.

**Borders & dividers.**
- Default border: `--hairline` (1px white @ 6% alpha). On parchment surfaces use `rgb(46 32 22 / 0.10)`.
- Sector dividers in-world are matte slate (`Sectors.dividerColor`); we mirror this in UI as `--divider` for sectional rules.

**Shadows.**
- All shadows are **warm-tinted** (brown-leaning, never neutral grey). Always paired: a tight 1–4px stack-edge offset (gives the chunky A-Hat-in-Time feel) plus a soft drop.
- The system has three shadow tiers (`--shadow-1/2/3`). Never invent a fourth.
- Inset shadows are reserved for **lit panels** (`--inset-warm`) and **pressed states**.

**Hover, press, focus.**
- **Hover:** lighten background by ~6% (raise to `--night-2`/`--night-3`). Buttons add a 1px lift on translateY.
- **Press:** drop the lift (translateY back to 0), darken background by ~4%, swap to `--inset-warm`. Goose and Fox press with a slight scale bounce (`--ease-pounce`); Buffalo presses with a heavier settle (`--ease-buffalo`).
- **Focus ring:** 2px outline in the active hero's `--core` color, offset 2px. Never a default browser ring.
- **Disabled:** opacity 0.4. No greying — preserves the warmth.

**Motion.**
- Three named eases: `--ease-out` (gentle settle, default), `--ease-pounce` (Goose/Fox), `--ease-buffalo` (heavier).
- Fades are short (`--dur-fast` 120ms) for hover; slides and reveals use `--dur-base` (220ms); scene transitions use `--dur-slow` (420ms).
- **No bounces on critical UI** (HP, wave timer). Bounces are reserved for cosmetic flourishes (hero-select pick confirm, level-up flash).
- Reduced-motion: collapse all transforms to opacity fades.

**Transparency & blur.**
- Blur is used **once**: behind the wave-banner overlay (`backdrop-filter: blur(8px)` over `--night-0` @ 60%). Anywhere else is forbidden — Roblox renders blur expensively.
- Transparency on cards is fine (`--inset-warm` uses alpha) but card backgrounds themselves are opaque.

**Imagery.**
- Where used, imagery is **warm-graded** — never cool/teal, never black-and-white, never grainy. The reference is the dawn-light end of Spiritfarer.
- Character renders are stylized low-poly with **slight proportion exaggeration** (bigger head, chunkier feet) — see `ui_kits/character_briefs/` for the canonical brief.

**Layout rules.**
- Fixed elements: HUD top-left (hero badge + HP), HUD top-right (wave + timer), HUD bottom-center (Val status when companion is active). Center is gameplay; never overlap.
- Modals are centered with a 60% night-0 scrim; never full-bleed.

---

## ICONOGRAPHY

The brand's iconography is **animal-totem-first, glyph-second**.

**Hero totems.**
- Each hero has a **silhouette mark** (head profile, single fill, no outline) used as the wayfinding icon throughout. Files in `assets/totems/` (PNG @ 512px, SVG fallback).
- The totem mark is **never used as a button affordance** — it identifies the hero's surface. For "switch to Goose" buttons, pair the totem with a glyph (e.g., arrow).

**Glyph icon set.**
- We use **Lucide** as the base glyph set (CDN: `https://unpkg.com/lucide-static@latest`). Reasoning: clean stroke (1.5px), rounded joints, matches Nunito's terminals.
- Stroke-based icons only. No filled glyphs in v0.1 (would compete with the solid totem marks).
- Standard sizes: 16, 20, 24, 32px. Never resize between.

**No emoji.** No unicode-as-icon (no `★`, `→`, `✓`). All glyphs come from Lucide so the visual rhythm is consistent.

**SVG vs PNG.**
- UI glyphs: **SVG via Lucide** (inlined or `<img>` referenced).
- Totem marks: SVG primary, PNG@2x fallback for Roblox ImageLabels (Roblox does not render SVG).
- Character renders: PNG only, exported from Blender.

**Substitution flag.**
- ⚠️ The repo has **no real logos or icon files yet** — `assets/` contains placeholder marks I generated as flat-color silhouettes. **Replace these** with Blender renders or hand-drawn marks before shipping. This is the single biggest gap.

---

## Font substitution flag

⚠️ No font files exist in the repo. I picked Google Fonts substitutes:
- **Young Serif** as a stand-in for the "chunky old-style display" the brief implies (Hades-leaning).
- **Nunito** for warm humanist body (Spiritfarer-leaning).
- **JetBrains Mono** for tactical/data text.

If you want a more A-Hat-in-Time chunk, consider **Recoleta** (paid, Pangram Pangram) for display. Drop `.woff2` files into `fonts/` and update the `@import` in `colors_and_type.css`.

---

## Index — where to look next

- **Building Roblox UI?** → `colors_and_type.css` + `ui_kits/hud/index.html`. Token names map 1:1 to suggested UDim2/Color3 values; comments inside the CSS show the source RGB.
- **Writing a Blender brief?** → `ui_kits/character_briefs/index.html`. Each character has a one-page brief: silhouette, palette, proportions, vibe.
- **Designing a slide or doc?** → Pull `colors_and_type.css` and use `--font-display` headlines on `--night-0`, body on `--parchment-0`.
- **Adding a new hero?** → Extend the totem palette in `Sectors.lua` first, then mirror in `colors_and_type.css`. Never the other way around.
