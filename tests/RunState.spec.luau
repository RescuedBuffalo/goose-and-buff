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
		"BUF-11: loss fires when every registered hero is down at the same time",
		function()
			-- Acceptance: every active hero down simultaneously must
			-- terminate the run. Matches the v0.1 spec's loss conditions
			-- alongside core destruction.
			local RunState = loadRunState()
			local state = RunState.new()
			local p1, p2, p3 = "p1", "p2", "p3"
			state:registerHero(p1)
			state:registerHero(p2)
			state:registerHero(p3)

			local results: { string } = {}
			state:onResult(function(r)
				table.insert(results, r)
			end)

			state:markHeroDown(p1)
			expect.eq(#results, 0, "1/3 down — no loss yet")
			state:markHeroDown(p2)
			expect.eq(#results, 0, "2/3 down — no loss yet")
			state:markHeroDown(p3)
			expect.eq(#results, 1, "3/3 down — loss fires")
			expect.eq(results[1], "loss")
		end,
	},
	{
		"BUF-11: a respawn (markHeroUp) before the last hero dies cancels loss",
		function()
			-- Tight respawn timing: if a downed hero comes back before the
			-- last teammate falls, all-down never reaches true and no
			-- loss fires.
			local RunState = loadRunState()
			local state = RunState.new()
			state:registerHero("p1")
			state:registerHero("p2")

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:markHeroDown("p1")
			state:markHeroUp("p1")  -- p1 respawns
			state:markHeroDown("p2") -- only p2 down: 1/2 alive
			expect.eq(fires, 0, "no loss while p1 alive")
			expect.nilish(state:result())
		end,
	},
	{
		"BUF-11: hero count of zero never auto-fires loss",
		function()
			-- Empty-server / spectator-only case: no heroes registered
			-- means we can't be all-down. The check must require at
			-- least one registered hero before evaluating.
			local RunState = loadRunState()
			local state = RunState.new()

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:markHeroDown("ghost") -- never registered
			expect.eq(fires, 0)
			expect.nilish(state:result())
		end,
	},
	{
		"BUF-11: unregisterHero removes the leaver from the alive check",
		function()
			-- Player quits mid-run. Their slot should not block the
			-- remaining heroes from being considered "all alive".
			local RunState = loadRunState()
			local state = RunState.new()
			state:registerHero("p1")
			state:registerHero("p2")
			state:markHeroDown("p2")

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:unregisterHero("p2") -- leaver
			-- Only p1 remains; p1 is alive; no loss.
			expect.eq(fires, 0)

			-- And re-evaluation still works for the survivors.
			state:markHeroDown("p1")
			expect.eq(fires, 1, "loss fires when last remaining hero falls")
		end,
	},
	{
		"BUF-11: unregistering the last alive hero leaves the survivors all-down → loss",
		function()
			-- Regression (Codex review on PR #15): if the only alive
			-- teammate disconnects while everyone else is already down,
			-- _heroCount drops but no markHeroDown event fires again.
			-- unregisterHero must re-run the all-down check or the run
			-- silently continues with every remaining hero dead.
			local RunState = loadRunState()
			local state = RunState.new()
			state:registerHero("p1")
			state:registerHero("p2")
			state:markHeroDown("p1") -- p1 down; p2 still alive

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:unregisterHero("p2") -- the only alive hero leaves
			expect.eq(fires, 1, "loss fires when leaver was the last alive hero")
			expect.eq(state:result(), "loss")
		end,
	},
	{
		"BUF-11: unregistering an already-down hero with alive teammates does not fire loss",
		function()
			-- Sentinel: unregisterHero shouldn't fabricate a loss while
			-- alive teammates remain. Only fires when the survivors are
			-- already all-down.
			local RunState = loadRunState()
			local state = RunState.new()
			state:registerHero("p1")
			state:registerHero("p2")
			state:markHeroDown("p1")

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:unregisterHero("p1") -- a downed leaver
			expect.eq(fires, 0, "p2 still alive — no loss")
			expect.nilish(state:result())
		end,
	},
	{
		"BUF-11: register/down/down sequence still fires loss exactly once",
		function()
			-- Even with multiple down events in a row, fire() guards keep
			-- the result callback at exactly one invocation.
			local RunState = loadRunState()
			local state = RunState.new()
			state:registerHero("p1")
			state:registerHero("p2")

			local fires = 0
			state:onResult(function() fires += 1 end)

			state:markHeroDown("p1")
			state:markHeroDown("p2")
			state:markHeroDown("p1") -- already down — no double-fire
			state:markHeroDown("p2")

			expect.eq(fires, 1)
			expect.eq(state:result(), "loss")
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
