--!strict
-- Tests for src/server/Systems/WaveDirector.lua.
-- Covers wave order, active-wave lifecycle (visibility window),
-- isFinished semantics, reset behavior, and the per-player visibility
-- contract that the BUF-91 reveal panel depends on.

local sandbox = require("./lib/sandbox")
local expect = require("./lib/expect")

local function loadDirector()
	local env = sandbox.makeEnv()
	return sandbox.loadModule("src/server/Systems/WaveDirector.lua", env)
end

-- Sample schedule that's small enough to step through manually.
local function sampleSchedule()
	return {
		{ time = 0, hero = "Fox" },
		{ time = 12, hero = "Goose" },
		{ time = 24, hero = "Buffalo" },
	}
end

return {
	{
		"start-gate: a director that has not been started ignores ticks",
		function()
			-- Regression: waves must not fire before :start(). We don't
			-- have a real Heartbeat in tests, but tick(dt) early-returns
			-- on _paused so the same gate is exercised.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())

			local fired: { string } = {}
			director:onWave(function(hero: string)
				table.insert(fired, hero)
			end)

			director:tick(60)

			expect.eq(#fired, 0, "wave fires while paused")
			expect.eq(director:elapsed(), 0, "elapsed advanced while paused")
			expect.falsy(director:isFinished(), "isFinished before start")
		end,
	},
	{
		"resume + tick activates waves in schedule order",
		function()
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			local fired: { string } = {}
			director:onWave(function(hero: string)
				table.insert(fired, hero)
			end)

			director:tick(0)
			expect.eq(#fired, 1, "after t=0 tick")
			expect.eq(fired[1], "Fox")

			director:tick(12)
			expect.eq(#fired, 2)
			expect.eq(fired[2], "Goose")

			director:tick(12)
			expect.eq(#fired, 3)
			expect.eq(fired[3], "Buffalo")

			expect.truthy(director:isFinished(), "isFinished after final wave")
		end,
	},
	{
		"isFinished only flips after every scheduled wave has activated",
		function()
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			expect.falsy(director:isFinished(), "before any tick")
			director:tick(0)
			expect.falsy(director:isFinished(), "after wave 1")
			director:tick(12)
			expect.falsy(director:isFinished(), "after wave 2")
			director:tick(12)
			expect.truthy(director:isFinished(), "after wave 3")
		end,
	},
	{
		"active waves expire after WAVE_VISIBILITY_SECONDS, freeing 'in combat'",
		function()
			-- Active state must clear after the visibility window so the
			-- reveal panel doesn't get stuck and teammate badges drop the
			-- IN COMBAT marker.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()
			director:setHeroResolver(function()
				return nil
			end)

			director:tick(0) -- Fox activates at t=0

			-- 1s later: still active.
			director:tick(1)
			local fakePlayer = newproxy(false)
			local view = director:getVisibleStateForPlayer(fakePlayer :: any)
			local foxRow
			for _, row in ipairs(view.teammates) do
				if row.heroId == "Fox" then
					foxRow = row
				end
			end
			expect.notNil(foxRow, "Fox row before expiry")
			expect.truthy(foxRow.inCombat, "Fox inCombat at t=1")

			-- WAVE_VISIBILITY_SECONDS is 10. Tick past it.
			director:tick(11)
			view = director:getVisibleStateForPlayer(fakePlayer :: any)
			foxRow = nil
			for _, row in ipairs(view.teammates) do
				if row.heroId == "Fox" then
					foxRow = row
				end
			end
			expect.notNil(foxRow)
			expect.falsy(foxRow.inCombat, "Fox inCombat after expiry")
		end,
	},
	{
		"onStateChanged fires when a wave activates and again when it expires",
		function()
			-- The HUD broadcaster relies on this to push fresh PlayerView
			-- to clients. Without per-state-change calls, expired waves
			-- would leave the reveal panel up.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			local stateChanges = 0
			director:onStateChanged(function()
				stateChanges += 1
			end)

			director:tick(0) -- activate Fox
			expect.truthy(stateChanges >= 1, "state-changed on activation")
			local afterActivate = stateChanges

			director:tick(11) -- past visibility window: Fox expires (no new wave at t=11)
			expect.truthy(stateChanges > afterActivate, "state-changed on expiry")
		end,
	},
	{
		"reveal: targeted player sees composition; teammates do not",
		function()
			-- BUF-91 spine: only the first-hit player gets the wave's
			-- composition. Teammates see a redacted in-combat row.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			local foxPlayer = newproxy(false)
			local goosePlayer = newproxy(false)
			director:setHeroResolver(function(p: any): string?
				if p == foxPlayer then
					return "Fox"
				elseif p == goosePlayer then
					return "Goose"
				end
				return nil
			end)

			director:tick(0) -- Fox wave goes active

			local foxView = director:getVisibleStateForPlayer(foxPlayer :: any)
			expect.eq(foxView.selfHeroId, "Fox")
			expect.truthy(foxView.selfInCombat, "Fox selfInCombat")
			expect.notNil(foxView.composition, "Fox composition revealed")

			local gooseView = director:getVisibleStateForPlayer(goosePlayer :: any)
			expect.eq(gooseView.selfHeroId, "Goose")
			expect.falsy(gooseView.selfInCombat, "Goose selfInCombat")
			expect.nilish(gooseView.composition, "Goose must NOT see Fox composition")

			-- Goose's teammate row for Fox should mark Fox as in combat
			-- but carry no composition payload anywhere on the view.
			local foxRowOnGoose
			for _, row in ipairs(gooseView.teammates) do
				if row.heroId == "Fox" then
					foxRowOnGoose = row
				end
			end
			expect.notNil(foxRowOnGoose)
			expect.truthy(foxRowOnGoose.inCombat, "Fox inCombat on Goose's view")
		end,
	},
	{
		"reset rewinds the schedule and clears active waves",
		function()
			-- BUF-92: same director must drive successive rounds.
			-- After reset the cursor returns to wave 1 and any active
			-- entries are gone.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()
			director:tick(0)
			director:tick(12)
			director:tick(12)
			expect.truthy(director:isFinished())

			director:reset()
			expect.falsy(director:isFinished(), "isFinished after reset")
			expect.eq(director:elapsed(), 0, "elapsed after reset")

			-- And it can run again from scratch.
			director:resume()
			local fired: { string } = {}
			director:onWave(function(hero: string)
				table.insert(fired, hero)
			end)
			director:tick(0)
			expect.eq(#fired, 1)
			expect.eq(fired[1], "Fox", "first wave after reset")
		end,
	},
	{
		"round1Schedule returns a defensive copy",
		function()
			local WaveDirector = loadDirector()
			local s1 = WaveDirector.round1Schedule()
			s1[1].hero = "Mutated"
			local s2 = WaveDirector.round1Schedule()
			expect.eq(s2[1].hero, "Fox", "canonical schedule preserved")
		end,
	},
	{
		"composition payload on the reveal matches shared/Data/Waves",
		function()
			-- The HUD reveal panel and the spawner both read from this
			-- table; if they diverge, the player sees a different wave
			-- than the spawner produces.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			local foxPlayer = newproxy(false)
			director:setHeroResolver(function(_p: any): string?
				return "Fox"
			end)

			director:tick(0)

			local view = director:getVisibleStateForPlayer(foxPlayer :: any)
			expect.notNil(view.composition)
			expect.eq(view.composition.name, "Recon Probe")
			expect.eq(#view.composition.enemies, 1)
			expect.eq(view.composition.enemies[1].type, "runner")
			expect.eq(view.composition.enemies[1].count, 6)
			expect.eq(view.composition.enemies[1].formation, "backline")
		end,
	},
}
