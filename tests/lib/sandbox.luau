--!strict
-- Lightweight Roblox-API sandbox so the gameplay systems can be required
-- and exercised under the standalone lune runtime, without Studio.
--
-- The systems-under-test do `require(game:GetService(...).X.Y)`, which
-- lune's path-based require can't satisfy directly. We work around that by
-- loading each system's source with a custom env: `game:GetService` returns
-- a synthesised tree, and `require` returns its argument unchanged when
-- handed a table (matching Roblox semantics where the table IS the module).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local sandbox = {}

-- ── Signals ────────────────────────────────────────────────────────────
-- Stand-in for RBXScriptSignal. Same surface as the engine's signal:
-- :Connect returns an object with :Disconnect, and :Fire invokes every
-- connected handler in registration order.
type Signal = {
	Connect: (Signal, (...any) -> ()) -> { Disconnect: (any) -> () },
	Fire: (Signal, ...any) -> (),
	_handlers: { [number]: ((...any) -> ())? },
}

local function newSignal(): Signal
	local self: any = { _handlers = {} }
	function self:Connect(fn)
		table.insert(self._handlers, fn)
		local idx = #self._handlers
		return {
			Disconnect = function()
				self._handlers[idx] = nil
			end,
		}
	end
	function self:Fire(...)
		-- Snapshot so a handler that disconnects mid-fire doesn't shift
		-- the iteration window.
		local snapshot = {}
		for i, h in pairs(self._handlers) do
			snapshot[i] = h
		end
		for _, h in pairs(snapshot) do
			h(...)
		end
	end
	return self
end
sandbox.newSignal = newSignal

-- ── Humanoid stub ──────────────────────────────────────────────────────
-- Just enough surface for RunState:bindCore — Health, MaxHealth,
-- HealthChanged, and a TakeDamage helper that drives HealthChanged.
type Humanoid = {
	Health: number,
	MaxHealth: number,
	HealthChanged: Signal,
	TakeDamage: (Humanoid, number) -> (),
	Kill: (Humanoid) -> (),
}

local function newHumanoid(maxHealth: number): Humanoid
	local self: any = {
		Health = maxHealth,
		MaxHealth = maxHealth,
		HealthChanged = newSignal(),
	}
	function self:TakeDamage(amount: number)
		self.Health = math.max(0, self.Health - amount)
		self.HealthChanged:Fire(self.Health)
	end
	function self:Kill()
		self.Health = 0
		self.HealthChanged:Fire(0)
	end
	return self
end
sandbox.newHumanoid = newHumanoid

-- ── Synthetic game tree ────────────────────────────────────────────────
-- Pre-required modules placed into a fake ReplicatedStorage tree. The
-- system code does `require(ReplicatedStorage.Data.Waves)`; our env's
-- `require` shim recognises a table argument and returns it directly.
local Waves = require("../../src/shared/Data/Waves")
local Heroes = require("../../src/shared/Data/Heroes")
local Constants = require("../../src/shared/Shared/Constants")

local function makeServices(): ({ [string]: any }, Signal)
	local heartbeat = newSignal()
	local services = {
		ReplicatedStorage = {
			Data = { Waves = Waves, Heroes = Heroes },
			Shared = { Constants = Constants },
		},
		RunService = { Heartbeat = heartbeat },
	}
	return services, heartbeat
end
sandbox.makeServices = makeServices

-- ── Env builder ────────────────────────────────────────────────────────
-- Builds the global env each system source runs under. `task.spawn` is
-- synchronous in tests so result fan-out is observable inline; `warn` is
-- swallowed unless the caller wires it up.
function sandbox.makeEnv(): ({ [string]: any }, { [string]: any }, Signal)
	local services, heartbeat = makeServices()

	local fakeGame = {
		GetService = function(_, name: string)
			local svc = services[name]
			if not svc then
				error("[sandbox] Unstubbed service: " .. name)
			end
			return svc
		end,
	}

	local env: { [string]: any } = {
		game = fakeGame,
		task = {
			-- Synchronous spawn so listeners run on the firing thread.
			-- The systems under test only use it to fan callbacks out
			-- past pcall boundaries; ordering doesn't matter for asserts.
			spawn = function(fn: (...any) -> (), ...)
				fn(...)
			end,
			defer = function(fn: (...any) -> (), ...)
				fn(...)
			end,
			wait = function(_t: number?)
				return 0
			end,
		},
		require = function(target: any)
			if type(target) == "table" then
				return target
			end
			error("[sandbox] require expected a table, got " .. type(target))
		end,
		warn = function(...) end,
		print = print,
		-- Standard library passthroughs.
		table = table,
		string = string,
		math = math,
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		select = select,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		typeof = function(x)
			return type(x)
		end,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		coroutine = coroutine,
		unpack = (table :: any).unpack,
		_G = {},
	}
	return env, services, heartbeat
end

-- ── Module loader ──────────────────────────────────────────────────────
-- Loads a Lua source file into the supplied env and runs it, returning
-- whatever the chunk returns. The chunk runs with `env` as its global
-- table, so its `game:GetService(...)` and `require(...)` calls hit our
-- shims rather than the engine.
function sandbox.loadModule(path: string, env: { [string]: any }): any
	local src = fs.readFile(path)
	-- lune sandboxes `load` / `loadstring` out of the default env; the
	-- `@lune/luau` module re-exports a sandboxed loader that takes the
	-- env via an `environment` field.
	local fn = luau.load(src, { environment = env })
	return fn()
end

return sandbox
