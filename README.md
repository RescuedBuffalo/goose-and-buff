# Goose-and-Buff

A private 3-player co-op Roblox roguelite for Aidan, Goose, and Beau. Animal-totem armies, sequential info-asymmetric waves, voice comms is the gameplay.

## Where things live

- **Game code** lives in the Roblox Studio place, not in this folder. This folder holds design docs and project files only. Connect via the Roblox Studio MCP to read/write scripts.
- **Design docs**: [`VISION.md`](VISION.md) for pillars and philosophy. [`v0.1-SPEC.md`](v0.1-SPEC.md) for the buildable contract.
- **Active work**: [Linear — buffalo-and-goose](https://linear.app/buffalo-studios/project/buffalo-and-goose-593efd9062a8). Milestones M1/M2/M3 cover the first playtest cycle.

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
