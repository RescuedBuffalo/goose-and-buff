# Thematic Units — v0.1 Data

> Drop this into `src/shared/Data/Units.lua` (or wherever your Rojo project puts it). Three archetypes × three factions = nine units. Mechanics are shared per archetype; per-faction stat tilts give each army a flavor.

## Theming framework

| Archetype | Goose (birds) | Buffalo (plains/savannah) | Fox (forest creatures) |
|---|---|---|---|
| Light melee (swarm) | **Gosling** | **Calf** | **Kit** |
| Ranged | **Heron** | **Ostrich** | **Lynx** |
| Heavy | **Swan** | **Longhorn** | **Badger** |

**Faction stat tilts** (vs. archetype baseline):
- **Goose**: cheaper, faster — swarm-leaning
- **Buffalo**: tankier, slower — anchor-leaning
- **Fox**: higher damage, lower HP — assassin-leaning

For v0.1, all 9 units share base mechanics per archetype. Visual skins differ but AI behavior, attack pattern, and animations are interchangeable. Iterate after the first playtest.

## Lua data

```lua
--!strict
-- Pure data: AI-controlled units that follow a hero.
--
-- Three archetypes shared across all factions: Light (swarm), Ranged, Heavy.
-- Each faction gets a thematic skin per archetype with a stat tilt:
--   Goose:   cheaper / faster (swarm)
--   Buffalo: tankier / slower (anchor)
--   Fox:     higher damage / lower HP (assassin)

local Units = {
    -- ========== GOOSE (birds, swarm-leaning) ==========
    Gosling = {
        id = "Gosling", faction = "Goose", archetype = "light", theme = "bird",
        health = 55, damage = 7, moveSpeed = 18,
        attackRange = 4, attackInterval = 0.7, cost = 22,
        flavor = "Cheap, scrappy, in numbers.",
    },
    Heron = {
        id = "Heron", faction = "Goose", archetype = "ranged", theme = "bird",
        health = 38, damage = 11, moveSpeed = 15,
        attackRange = 32, attackInterval = 1.2, cost = 35,
        flavor = "Long spear-strike. Stays in the back.",
    },
    Swan = {
        id = "Swan", faction = "Goose", archetype = "heavy", theme = "bird",
        health = 130, damage = 13, moveSpeed = 12,  -- faster than baseline heavy
        attackRange = 4, attackInterval = 1.4, cost = 70,
        flavor = "Hisses. Charges. Surprisingly mean.",
    },

    -- ========== BUFFALO (plains/savannah, anchor-leaning) ==========
    Calf = {
        id = "Calf", faction = "Buffalo", archetype = "light", theme = "plains",
        health = 70, damage = 6, moveSpeed = 14,  -- tougher / slower than baseline light
        attackRange = 4, attackInterval = 0.8, cost = 28,
        flavor = "Wide stance from the start.",
    },
    Ostrich = {
        id = "Ostrich", faction = "Buffalo", archetype = "ranged", theme = "plains",
        health = 55, damage = 14, moveSpeed = 13,
        attackRange = 14, attackInterval = 1.3, cost = 40,  -- close-range "ranged" w/ knockback
        knockbackStuds = 6,
        flavor = "Kicks at mid-range. Knockback included.",
    },
    Longhorn = {
        id = "Longhorn", faction = "Buffalo", archetype = "heavy", theme = "plains",
        health = 180, damage = 14, moveSpeed = 9,
        attackRange = 4, attackInterval = 1.6, cost = 80,
        flavor = "The wall. Don't try to go through.",
    },

    -- ========== FOX (forest creatures, assassin-leaning) ==========
    Kit = {
        id = "Kit", faction = "Fox", archetype = "light", theme = "forest",
        health = 42, damage = 8, moveSpeed = 22,  -- fastest light
        attackRange = 3, attackInterval = 0.6, cost = 25,
        flavor = "Faster than it should be. Bites.",
    },
    Lynx = {
        id = "Lynx", faction = "Fox", archetype = "ranged", theme = "forest",
        health = 35, damage = 16, moveSpeed = 18,
        attackRange = 22, attackInterval = 1.5, cost = 45,
        ambushDamageBonus = 1.5,  -- +50% damage if attacking from outside enemy aggro
        flavor = "Stalks. Strikes once, hard.",
    },
    Badger = {
        id = "Badger", faction = "Fox", archetype = "heavy", theme = "forest",
        health = 110, damage = 16, moveSpeed = 11,
        attackRange = 4, attackInterval = 1.5, cost = 70,
        evasionChance = 0.10,  -- 10% chance to dodge an incoming hit
        flavor = "Stocky and stubborn. Hard to pin down.",
    },
}

return Units
```

## Notes for whoever wires this up

- Treat `archetype` as the AI-behavior key. The renderer / animator picks visuals from `theme` + `id`.
- `knockbackStuds`, `ambushDamageBonus`, `evasionChance` are optional and apply only to specific units. Most code paths can ignore them in v0.1.
- Faction tilts are ~10–15% off baseline. Don't compound on top of skill-tree multipliers without testing — easy to push these into broken territory.
- Visuals: for the v0.1 playtest, "different skin" can be different colors/shapes on the same base mesh. Real Blender renders are a separate workstream (see Linear `[Visual polish]` issue).
