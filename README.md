# Goose-and-Buff

A private 3-player co-op Roblox roguelite for Aidan, Goose, and Beau. Animal-totem armies, sequential info-asymmetric waves, voice comms is the gameplay.

## Where things live

- **Game code** lives in the Roblox Studio place, not in this folder. This folder holds design docs and project files only. Connect via the Roblox Studio MCP to read/write scripts.
- **Design docs**: [`VISION.md`](VISION.md) for pillars and philosophy. [`v0.1-SPEC.md`](v0.1-SPEC.md) for the buildable contract.
- **Active work**: [Linear — buffalo-and-goose](https://linear.app/buffalo-studios/project/buffalo-and-goose-593efd9062a8). Milestones M1/M2/M3 cover the first playtest cycle.

## Toolchain

Toolchain versions are pinned in [aftman.toml](aftman.toml). Install
[Aftman](https://github.com/LPGhatguy/aftman), then from the repo root:

```sh
aftman install
```

That gives you `rojo` (project builder / sync server) and `lune` (used by
the test runner below).

## Building / serving

```sh
rojo serve   # connect from Studio's Rojo plugin
rojo build default.project.json -o goose-and-buff.rbxlx
```

## Running tests

The deterministic gameplay systems (`RunState`, `WaveDirector`, the
`Combat` registry) are covered by a [lune](https://lune-org.github.io/docs)
test suite under [`tests/`](tests). Run it from the repo root:

```sh
lune run tests
```

Each `tests/*.spec.luau` returns an ordered list of `{ name, fn }` cases;
[`tests/init.luau`](tests/init.luau) discovers them and prints a per-spec
summary, exiting non-zero on any failure.

The systems load through a small sandbox in
[`tests/lib/sandbox.luau`](tests/lib/sandbox.luau) that stubs the Roblox
APIs the systems touch (`game:GetService`, `task.spawn`, `Humanoid`-shaped
mocks). Pure data modules under `src/shared/Data` and `src/shared/Shared`
are required directly by lune.

Adapter code under `src/server/Adapters` (WaveSpawner, WorldBuilder)
leans on Roblox-only APIs — `Workspace`, `Instance.new`, `CFrame`, etc.
— and is intentionally left out of the unit suite. Smoke-test those
in-Studio after a `rojo serve` session.

### Adding a test

1. Drop a new `tests/<Module>.spec.luau` that returns
   `{ { "case name", function() ... end }, ... }`.
2. Register it in [`tests/init.luau`](tests/init.luau)'s `specs` list.
3. Use [`tests/lib/expect.luau`](tests/lib/expect.luau) for assertions
   (`expect.eq`, `expect.truthy`, `expect.deepEq`, ...).

If the module-under-test does `require(game:GetService(...).Foo.Bar)`,
load it through `sandbox.loadModule` so the sandbox's shimmed `game`
and `require` come into scope. If it's a pure module (no Roblox APIs),
require it directly.

## Place layout

```
ReplicatedStorage/
    Data/         -- pure tables: Heroes, Units, Abilities, Waves
    Shared/       -- Constants, types used by client + server
    Remotes/      -- created by NetworkAdapter on boot
ServerScriptService/
    GameLogic/    -- pure Luau, no Roblox APIs: WaveDirector, SkillTree, AbilityResolver, Economy
    Adapters/     -- Roblox-aware: NetworkAdapter, WaveSpawner
    Main          -- boot script that wires GameLogic to Adapters
StarterPlayer/StarterPlayerScripts/
    HeroController, InputAdapter, UI/
```

## Architecture rules (load-bearing)

The codebase is split into three layers on purpose. Code that violates the split creates work later — both when iterating and if we ever rebuild in another engine.

1. **Pure logic** in `ServerScriptService/GameLogic/*`. No Roblox API calls. No `game:GetService`, no `Instance.new`, no `task.wait`. State machines and pure functions only — inputs and outputs.
2. **Roblox-aware adapters** in `ServerScriptService/Adapters/*`. This is where `Workspace`, `Players`, `RemoteEvent`, etc. are allowed. Adapters subscribe to GameLogic events and translate them into world effects (and vice versa).
3. **Pure data** in `ReplicatedStorage/Data/*`. Plain Luau tables. Easy to inspect, balance, copy-paste. No logic.

Shared client+server constants live in `ReplicatedStorage/Shared/Constants.lua`. The `REMOTES` table there is the canonical RemoteEvent name registry — add to it before using a new remote.

## Existing APIs — reuse, don't re-derive

When picking up an issue, check whether the system already exists before writing it:

- `WaveDirector:on(eventName, callback)` emits `roundStart(roundIndex)`, `waveStart(playerId, waveData)`, `roundEnd(roundIndex)`.
- `WaveDirector:getVisibleStateForPlayer(playerId)` already returns the per-player visibility for the info-asymmetry mechanic. **Don't re-derive who sees what — render this state.**
- `WaveDirector:tick(dt)` is pure dt-driven. Heartbeat-driven coordination wraps this from an adapter; never put a Heartbeat connection inside GameLogic.
- `AbilityResolver.resolve(abilityId, casterState, targetingPayload)` produces a pure-data list of effects. Adapters apply effects to Workspace.
- `SkillTree.new(heroId)`, `:grantPoint()`, `:canUnlock(nodeId)`, `:unlock(nodeId)`, `:getActiveEffects()` — per-player skill tree state.
- `Economy.new(playerId)`, `:tick(dt)`, `:spend(amount)`, `:upgradeProduction()` — coin generation and spending.
- `NetworkAdapter.init()`, `.fireClient(player, name, payload)`, `.fireAllClients(name, payload)`, `.onServerEvent(name, callback)` — RemoteEvent surface, name-registry-driven.

## Conventions and anti-patterns

- **Don't put `wait()` / `task.wait()` inside GameLogic modules.** Time progression is `tick(dt)`-driven. Sleeps belong in adapters.
- **Don't broadcast wave composition automatically.** First-hit-only visibility is the spine mechanic. Always go through `getVisibleStateForPlayer`.
- **Don't add new RemoteEvents without registering them in `Constants.REMOTES`.** Otherwise client and server drift.
- **Don't bake stats inline in adapter code.** Read from `ReplicatedStorage/Data/*`. Balancing is iteration #1 after every playtest; centralized data tables make tweaks cheap.
- **Don't import GameLogic modules into client LocalScripts.** The server is authoritative. Clients render state and send inputs.
- **Don't restructure existing event listener wiring** when adding to an adapter. The pattern is: `someAdapter.attach(gameLogicModule)` and the adapter subscribes via `:on(eventName, callback)`. Replace `print` calls inside listeners; don't rebuild the listener flow.

## Workflow for picking up an issue

1. Read the Linear issue. Note the acceptance criteria and any "out of scope" notes.
2. Identify which layer the work belongs to: pure logic, adapter, data, or client.
3. Check the "Existing APIs" section above — reuse before re-deriving.
4. Implement. Use the Roblox Studio MCP for live iteration when available.
5. Verify with a play-test. Watch the console for errors. For pure-logic changes, a smoke-test in `Main.lua` is faster than full play.
6. Comment on the Linear issue with what shipped, what was descoped, and any open questions for the PM conversation.

## Style

- Luau, server-authoritative.
- Prefer `ModuleScript` over `Script`. The boot script (`Main`) is the only top-level `Script`.
- Comments explain *why*, not *what*. Code should read naturally enough that the *what* is obvious.
- Keep public functions small and named for their effect. Internal helpers prefixed with `_`.
