--!strict
-- Tests for src/server/Systems/RunState.lua.
-- Covers: core-loss, multi-core (all-heroes-downed) loss, win path,
-- exactly-once result firing, late-listener catch-up.

local sandbox = require("./lib/sandbox")
local expect = require("./lib/expect")

local function loadRunState()
	local env = sandbox.makeEnv()
	return sandbox.loadModule("src/server/Systems/RunState.lua", env)
end

return {
	{
		"fires loss when a single bound core's HP hits zero",
		function()
			local RunState = loadRunState()
			local state = RunState.new()
			local core = sandbox.newHumanoid(1000)
			state:bindCore(core)

			local results: { string } = {}
			state:onResult(function(r)
				table.insert(results, r)
			end)

			expect.nilish(state:result(), "result before damage")
			core:Kill()

			expect.eq(state:result(), "loss")
			expect.eq(#results, 1)
			expect.eq(results[1], "loss")
		end,
	},
	{
		"all-heroes-downed: loss fires exactly once even when every core dies",
		function()
			-- Regression: if multiple cores die in sequence, the result
			-- callback must fire once, not once per core.
			local RunState = loadRunState()
			local state = RunState.new()
			local cores = { sandbox.newHumanoid(100), sandbox.newHumanoid(100), sandbox.newHumanoid(100) }
			for _, h in ipairs(cores) do
				state:bindCore(h)
			end

			local fires = 0
			state:onResult(function()
				fires += 1
			end)

			for _, h in ipairs(cores) do
				h:Kill()
			end

			expect.eq(fires, 1, "loss callback fire count")
			expect.eq(state:result(), "loss")
		end,
	},
	{
		"setResult('win') fires win exactly once",
		function()
			local RunState = loadRunState()
			local state = RunState.new()

			local results: { string } = {}
			state:onResult(function(r)
				table.insert(results, r)
			end)

			state:setResult("win")
			state:setResult("win")
			state:setResult("loss")

			expect.eq(#results, 1, "callback count")
			expect.eq(results[1], "win")
			expect.eq(state:result(), "win")
		end,
	},
	{
		"first terminal result wins; subsequent setResult calls are no-ops",
		function()
			local RunState = loadRunState()
			local state = RunState.new()

			local results: { string } = {}
			state:onResult(function(r)
				table.insert(results, r)
			end)

			state:setResult("loss")
			state:setResult("win")

			expect.eq(#results, 1)
			expect.eq(results[1], "loss")
			expect.eq(state:result(), "loss")
		end,
	},
	{
		"loss from bindCore latches; later setResult('win') is ignored",
		function()
			local RunState = loadRunState()
			local state = RunState.new()
			local core = sandbox.newHumanoid(50)
			state:bindCore(core)

			local results: { string } = {}
			state:onResult(function(r)
				table.insert(results, r)
			end)

			core:Kill()
			state:setResult("win")

			expect.eq(#results, 1)
			expect.eq(results[1], "loss")
		end,
	},
	{
		"late onResult listener is fired immediately with the latched result",
		function()
			local RunState = loadRunState()
			local state = RunState.new()
			state:setResult("win")

			local seen: string? = nil
			state:onResult(function(r)
				seen = r
			end)

			expect.eq(seen, "win")
		end,
	},
	{
		"core HealthChanged at HP > 0 does not fire loss",
		function()
			-- Regression: only the <=0 transition is terminal. A graze
			-- that drops health but leaves the core alive must not fire.
			local RunState = loadRunState()
			local state = RunState.new()
			local core = sandbox.newHumanoid(100)
			state:bindCore(core)

			local fires = 0
			state:onResult(function()
				fires += 1
			end)

			core:TakeDamage(50)
			core:TakeDamage(49)

			expect.eq(fires, 0)
			expect.nilish(state:result())
		end,
	},
}
