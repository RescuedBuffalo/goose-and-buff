# Vision: Goose, Buffalo, Fox

## Working title

**The Long Watch** — proposed by the v1 design system. The pitch: *the lights are low, the friends are at their posts, the watch is long.* Captures the wave-defense rhythm. Working code name remains "Goose-and-Buff" / "buffalo-and-goose" (Linear) until the title is ratified.

## One-line pitch

A 3-player co-op Roblox roguelite where you command animal-totem armies through info-asymmetric waves, surviving by talking, trading, and trusting each other.

## Who this is for

Three people who already play together over voice almost every night — Valorant, ARK, Once Human, Roblox tycoons, Schedule 1, Overcooked, 99 Nights in the Forest. This is a game built around *how they actually play*, not a game that hopes to teach them new habits.

- **Buffalo** — defensive anchor, the heavy
- **Goose** — aggression specialist, IGL, calls plays
- **Fox** — cunning, opportunistic, often the first to be ganged up on
- **Val** — black tri-color Australian Shepherd, shared mascot, roams between sectors

## Design pillars

### 1. Strategy first, action second

Roughly 60% of skill lives in pre-wave economy, composition, and skill-tree decisions. ~30% in hero positioning and ability timing. ~10% in RNG (crits, terrain). The pre-wave phase is where the real game happens; the wave phase is where you find out if your prep was right.

### 2. Voice comms IS gameplay

Information is asymmetric on purpose. Whoever gets hit first sees the wave composition; the others see only "in combat" status. The first-hit player MUST call it out for the team to adapt. The game doesn't replace your callouts — it requires them. This is not a "voice optional" co-op game.

### 3. Co-op with quiet competition

You're all on the same team. There's no PvP. But personal RNG, personal builds, and visible carry/falling-behind moments mean every run is a story of who popped off and who got cooked. The Roblox-tycoon "we're all spinning, who got the legendary?" energy.

### 4. Hard. Lose. Upgrade. Try again.

Hades-style roguelite structure. Each run ends, often badly. Failure unlocks meta-progression: more abilities, more units, deeper skill trees. Losing isn't punishment — it's how the game grows.

### 5. Personal through totems, not autobiography

Goose, Buffalo, Fox, Val. The lodge hub between runs. The aesthetic, the inside jokes, the trophy wall — that's where it feels like *theirs*. The game systems are clean and impersonal; the flavor layer is the love letter. No literal cities, no relationship-quiz mechanics, no narrative quests about meeting in SF.

### 6. Modifiable as a feature

The dev is also a player. The audience is a fixed group of three. New units, abilities, and tree branches drop in as roguelite meta-unlocks — content development IS the in-game progression curve. Each playtest reveals what's missing; the next dev cycle adds it.

## Roles (Valorant trinity, animal-shaped)

| Role | Animal | Valorant analogue | Job |
|---|---|---|---|
| Aggression / IGL | Goose | Duelist (Yoru/Jett-IGL) | First in, calls tempo, sets plays |
| Anchor | Buffalo | Sentinel | Holds the line, soaks damage, AoE control |
| Recon / Raider | Fox | Initiator | Flanks, scouts, opportunistic loot |
| Companion | Val | (none — Aussie shepherd) | Shared roaming utility unit, herder |

## Core loop

**Between runs (the Lodge):** spend meta-currency on permanent unlocks. Unlock new abilities, units, tree branches. Decorate. Pet Val. The Lodge grows alongside the game itself — every dev cycle adds something to the hub.

**In-run, per round:**

1. **Prep phase.** Build economy, compose army, spend skill points.
2. **Wave phase.** Waves hit players sequentially in a rotating order. First-hit calls the wave; others adapt. Heroes control armies that follow them. Support abilities cross sectors.
3. **Debrief.** Collect drops, level up, decide what to do with the round's gains.

## Platform

**Built in Godot 4.** The reasoning, in short:

- 2D is a first-class citizen in Godot. The hand-drawn illustrated aesthetic (Hades / Spiritfarer / Root references) is what the engine was built for.
- Multiplayer via Godot's `MultiplayerAPI` is small in scope for a 3-player game — host-and-connect over ENet, no third-party services required.
- Open source, free, no runtime fees, no platform monetization rules.
- The architectural discipline (pure logic / adapter / data) ported cleanly from the original Roblox version — pivots like this are why we split layers in the first place.
- A Godot MCP exists for AI-assisted development (scene editing, script read/write, live play-test, screenshot, scene-tree inspection). Build loop is fast.

Godot's trade-offs vs. Roblox are real but acceptable for our audience: distribution requires sending a build (Discord file or itch.io private link rather than a place URL), and multiplayer needs glue code where Roblox handed it to us. For three friends willing to install one game, this is a non-issue.

The original Roblox build of this game lived briefly. The pivot happened cheaply because the design docs, data tables, and pure-logic patterns ported verbatim — only the engine-specific adapters and scene-building code needed rewriting. If we ever leave Godot, the same discipline applies: rebuild rather than port, lean on the data + logic layers staying portable.

## What this is NOT

- **Not a story game.** No dialogue trees, no romance arcs, no narrative quests.
- **Not autobiographical.** The map is not their cities. The bosses are not their relatives. Personal flavor lives in totems and easter eggs, not the spine.
- **Not PvP.** Friction yes, betrayal no.
- **Not asynchronous.** Real-time multiplayer. All three players online together for a run.
- **Not aiming for the Roblox front page.** This is a private game for three. Discoverability, monetization, and Roblox audience norms don't apply.

## Long-term parking lot

Ideas worth keeping alive but explicitly out of scope for early versions:

- **Migration / cities content** — once the core is humming, a Vietnam expansion or city-themed map pack could land as DLC-style content
- **Heist / raid mode** — Fox leads sorties out of the sector to steal from NPC factions
- **Val depth** — minigame, leveling, equipment, named tricks
- **Inter-sector friction mechanics** — intentional sabotage between teammates (only after the cooperative core is rock-solid)
- **Trophy wall as easter-egg layer** — slow drip of personal flavor unlocks tied to real-life dates and milestones

## Riskiest assumptions

These are the design bets that could break the game and need to be tested live:

1. **The 60/30/10 split feels right in play.** Active layers are more salient than passive ones — the 30% hero layer might dominate attention even if it's "supposed" to be secondary.
2. **Info-asymmetry feels like fun pressure, not stressful chaos.** Hidden information can be exhilarating or frustrating depending on the implementation. Test it early.
3. **The "carry vs. falling behind" tension is fun for the same person twice.** If Beau is the falling-behind player every run, he stops showing up. Personal RNG + rubber-banding + rotating roles need to actually work.
4. **Roblox depth is enough for what we want.** The platform has a real technical ceiling. Tens of AI units per player, complex skill trees, layered ability interactions — all comfortably inside the envelope. But if a specific later system (e.g., very dense unit simulation, custom shaders) hits a wall, that's the signal to rebuild elsewhere — not to compromise the design to fit the engine.
