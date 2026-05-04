# Goose-and-Buff — Design System Brief for Claude Design

> Paste this into Claude Design as a single brief. Edit anything that doesn't match your taste before you send. Reference docs (VISION.md, v0.1-SPEC.md, README.md) live alongside this file in the project folder — share them if Claude Design wants more context.

---

## Project context

Goose-and-Buff is a **private 3-player co-op Roblox roguelite** for three friends who play games together over voice almost every night. It's a personal project for a fixed audience — not a public release, no front-page chase, no monetization concerns.

The three players each command one of three **animal-totem heroes**:

- **Goose** — aggression specialist + IGL. Calls plays, takes space first.
- **Buffalo** — sentinel anchor. Heavy, rooted, soaks damage.
- **Fox** — initiator/recon. Cunning, opportunistic, flanks.

The fourth recurring character is **Val**, an Australian Shepherd who roams between sectors as a shared NPC companion (modeled after the dev's real dog — black tri-color Aussie shepherd).

The game's most relevant design pillar for you: **personal through totems, not autobiographical.** The aesthetic, character design, and inside-joke flavor are how the game feels like *theirs* without being a literal museum of their life. The systems are clean and impersonal; the visual layer is the love letter.

## What this brief is asking for

A complete **v0.1 design system file** that covers identity, characters, enemies, sectors, and UI — at enough fidelity that downstream tools (Blender + Claude MCP for 3D, Roblox Studio for UI) can produce assets directly from your specs.

Specifically:

1. **Visual identity tokens** — color palette (full + per-faction), typography (Roblox-compatible), motion language, tonal direction
2. **Faction design system** — how Goose / Buffalo / Fox are differentiated visually at a glance (color, silhouette, motif). Val's companion identity.
3. **Hero character briefs (×4)** — Blender-ready: silhouette, palette w/ hex, shape language, attitude, scale (in studs), poly target. One each for Goose, Buffalo, Fox, Val.
4. **Enemy archetype briefs (×3)** — same shape, for `GruntMelee`, `GruntRanged`, `Bruiser` (the v0.1 enemies defined in the spec).
5. **Sector visual identity** — what makes each faction's sector legibly *theirs* at a distance: terrain, color zoning, environmental motifs.
6. **UI component library (v0.1 HUD)** — Roblox-ScreenGui-shaped specs for:
   - Sector core HP indicator
   - Teammate portrait card (hero name, "in combat" badge, core HP %)
   - First-hit player's wave composition panel
   - Round/run state indicator (round 1/2/3, prep timer, wave timer)
   - Win/loss end screens
7. **Placeholder briefs for v0.2+ components** — lodge hub, skill tree node, ability cooldown indicator. Low fidelity is fine; just enough to anchor the visual language.

## Style constraints

- **Stylized, low-poly.** Blender-output friendly. Reads at distance. No PBR realism.
- **Roblox-native rendering should be a feature, not a fight.** Slight exaggeration of proportions is welcome. Don't try to make it look like Unreal.
- **Tonal target: cozy but tactical.** Warm, inviting palettes. Crunchy mechanical legibility — you should always be able to tell melee from ranged at a glance.
- **Three faction palettes that read at distance.** Color + silhouette do the legibility work. Don't lean on labels or icons.
- **Animal personality first, mechanics second.** Goose looks like a goose first and an aggression specialist second. Buffalo looks like a buffalo first and an anchor second. No generic creatures wearing role-badges.
- **Reference vibe**: somewhere between *Spiritfarer*, *Hades*, and *A Hat in Time*. Stylized, slightly chunky, with personality. Not Disney-cute. Not grimdark.

## Faction starting points (push back if you disagree)

These are my instincts, not commitments. If you have a stronger direction, take it:

- **Goose** (aggression / IGL) — high-contrast cool palette: white + slate blue + a punch of crimson. Lean, forward-leaning silhouette. Sharp angles. Should look like a bird that *commands*, not a bird that wanders.
- **Buffalo** (sentinel anchor) — earth palette: clay brown + warm umber + dark green. Heavy, rooted silhouette. Wide stance. Built like a wall.
- **Fox** (initiator/recon) — warm palette: rust orange + cream + dusk purple accent. Low, fluid silhouette. Sneaky posture. Looks about to dart.
- **Val** (Aussie shepherd companion) — black + tri-color (rust + white) per real-life Val. Energetic, alert. Smaller than the heroes — companion scale, not creature scale.

## Asset handoff requirements

Downstream tooling matters. Format your briefs with the next tool in mind:

**For Blender + Claude (3D characters and enemies):**
- Concise silhouette description (one sentence that fits in a Blender prompt)
- Specific hex color values
- Shape language (boxy / curved / angular / segmented)
- Pose reference (standing, crouched, alert, lunging, etc.)
- Approximate poly target (low-poly stylized — say a range like 800–2000 tris)
- Scale in Roblox studs

**For Roblox Studio (UI):**
- Specs in terms that map to `Frame`, `TextLabel`, `ImageLabel`, `UIStroke`, `UICorner`, `UIGradient`, `UIPadding`, `UIListLayout`, etc.
- No CSS-only patterns that don't translate (e.g., no flexbox `gap` properties — use `UIListLayout.Padding`)
- Color values referenced from the token palette, not hardcoded

## Output format

A single markdown design-system doc structured like:

1. **Visual identity** — color tokens (full palette + per-faction), typography, motion, tonal direction
2. **Faction system** — palettes, motifs, do/don't grid
3. **Hero briefs** (one per character, Blender-ready)
4. **Enemy briefs** (one per archetype, Blender-ready)
5. **Sector visual identity**
6. **UI component library** (v0.1, Roblox-Studio-ready)
7. **Future component placeholders** (v0.2+)
8. **Open questions / decisions surfaced for PM review**

Where useful, include Figma frames or generated mockup images for UI components.

## Where to surface decisions vs. ship them

When you hit anything where you'd want a PM call, surface it as an **Open Question** rather than committing. Specifically:

- Tonal calibration (cozier vs. more competitive?)
- Trade-offs that lock content direction (e.g., committing to a specific era/biome)
- Anything that would be expensive to back out of

I'd rather pause and align than ship a design that paints us into a corner. Otherwise, take strong positions and ship.

## Out of scope for v0.1 design

- Marketing assets, splash screens, store thumbnails (no public release)
- Animation rigs (Blender stage will handle that)
- Sound design (separate workstream)
- Lodge hub interior fidelity (placeholder is fine — proper hub design is a v0.2 brief)
- Skill-tree visual treatment beyond "a node looks like *this*"

## Things that already exist (don't re-derive)

- The three heroes and their roles, defined in `ReplicatedStorage.Data.Heroes`
- Enemy archetypes and stats in `ReplicatedStorage.Data.Waves.Enemies`
- Color totem instinct above (push back if you disagree, but it's your starting frame)
- Game architecture (this is design-system-only — engineering is handled separately)
