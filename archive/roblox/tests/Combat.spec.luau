--!strict
-- Smoke tests for src/server/Systems/Combat.lua's pure registry surface.
-- The ClickDetector wiring (bindEnemyClicks) lives behind Roblox-only
-- APIs and is left for in-Studio smoke tests; this file covers the
-- player→hero binding the rest of the server (and BUF-91's HeroResolver)
-- depends on.

local sandbox = require("./lib/sandbox")
local expect = require("./lib/expect")

local function loadCombat()
	local env = sandbox.makeEnv()
	return sandbox.loadModule("src/server/Systems/Combat.lua", env)
end

return {
	{
		"heroFor returns nil for unbound players",
		function()
			local Combat = loadCombat()
			local p = newproxy(false)
			expect.nilish(Combat.heroFor(p :: any))
		end,
	},
	{
		"bindPlayer / heroFor / unbindPlayer round-trip",
		function()
			local Combat = loadCombat()
			local p = newproxy(false)
			Combat.bindPlayer(p :: any, "Fox")
			expect.eq(Combat.heroFor(p :: any), "Fox")

			Combat.unbindPlayer(p :: any)
			expect.nilish(Combat.heroFor(p :: any))
		end,
	},
	{
		"bindings are per-player; binding one does not affect another",
		function()
			local Combat = loadCombat()
			local p1 = newproxy(false)
			local p2 = newproxy(false)
			Combat.bindPlayer(p1 :: any, "Fox")
			Combat.bindPlayer(p2 :: any, "Goose")

			expect.eq(Combat.heroFor(p1 :: any), "Fox")
			expect.eq(Combat.heroFor(p2 :: any), "Goose")

			Combat.unbindPlayer(p1 :: any)
			expect.nilish(Combat.heroFor(p1 :: any))
			expect.eq(Combat.heroFor(p2 :: any), "Goose")
		end,
	},
	{
		"rebinding a player overwrites the prior hero",
		function()
			local Combat = loadCombat()
			local p = newproxy(false)
			Combat.bindPlayer(p :: any, "Fox")
			Combat.bindPlayer(p :: any, "Goose")
			expect.eq(Combat.heroFor(p :: any), "Goose")
		end,
	},
}
