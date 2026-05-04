# goose-and-buff

A Roblox co-op tower-defence prototype, built with [Rojo](https://rojo.space).

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
