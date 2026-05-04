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
		"BUF-10: active waves persist until endWave is called, not on a timer",
		function()
			-- Regression: the v0.1 stub auto-expired waves after 10s. That
			-- broke BUF-91 — teammates' "IN COMBAT" badges dropped while
			-- enemies were still attacking the sector. Now combat state
			-- stays until the adapter signals enemies have cleared.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()
			director:setHeroResolver(function()
				return nil
			end)

			director:tick(0) -- Fox activates at t=0
			local fakePlayer = newproxy(false)

			local function foxRow()
				local view = director:getVisibleStateForPlayer(fakePlayer :: any)
				for _, row in ipairs(view.teammates) do
					if row.heroId == "Fox" then
						return row
					end
				end
				return nil
			end

			-- Far past the old 10s window — combat state must persist.
			director:tick(60)
			local row = foxRow()
			expect.notNil(row, "Fox row at t=60")
			expect.truthy(row.inCombat, "Fox inCombat at t=60 (no auto-expiry)")

			-- Explicit clear closes the wave.
			director:endWave("Fox")
			row = foxRow()
			expect.notNil(row)
			expect.falsy(row.inCombat, "Fox inCombat after endWave")
		end,
	},
	{
		"endWave is a no-op for a hero with no active wave",
		function()
			-- Idempotency: an over-eager adapter that calls endWave twice
			-- (e.g. after the last enemy dies AND on round-cleanup) must
			-- not double-fire onStateChanged.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()

			local stateChanges = 0
			director:onStateChanged(function()
				stateChanges += 1
			end)

			director:endWave("Fox") -- nothing active
			expect.eq(stateChanges, 0, "no state change for noop endWave")

			director:tick(0)
			local afterActivate = stateChanges
			director:endWave("Fox")
			expect.eq(stateChanges, afterActivate + 1, "first endWave fires once")
			director:endWave("Fox")
			expect.eq(stateChanges, afterActivate + 1, "second endWave is silent")
		end,
	},
	{
		"onStateChanged fires when a wave activates and when endWave clears it",
		function()
			-- The HUD broadcaster relies on this to push fresh PlayerView
			-- to clients on every active-set transition.
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

			director:endWave("Fox")
			expect.truthy(stateChanges > afterActivate, "state-changed on endWave")
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
		"BUF-12: scheduleForRound returns the rotated lead hero per round",
		function()
			-- v0.1 spec: round 1 leads with Fox, round 2 with Buffalo,
			-- round 3 with Goose. Verifying the lead hero per round
			-- guards against the schedules being silently swapped.
			local WaveDirector = loadDirector()
			expect.eq(WaveDirector.scheduleForRound(1)[1].hero, "Fox")
			expect.eq(WaveDirector.scheduleForRound(2)[1].hero, "Buffalo")
			expect.eq(WaveDirector.scheduleForRound(3)[1].hero, "Goose")
			expect.eq(WaveDirector.totalRounds(), 3)
		end,
	},
	{
		"BUF-12: scheduleForRound returns a defensive copy",
		function()
			local WaveDirector = loadDirector()
			local s = WaveDirector.scheduleForRound(2)
			s[1].hero = "Mutated"
			local s2 = WaveDirector.scheduleForRound(2)
			expect.eq(s2[1].hero, "Buffalo", "canonical round 2 schedule preserved")
		end,
	},
	{
		"BUF-12: out-of-range round falls back to round 1 (does not error)",
		function()
			local WaveDirector = loadDirector()
			local s = WaveDirector.scheduleForRound(99)
			expect.eq(s[1].hero, "Fox", "fallback schedule is round 1")
		end,
	},
	{
		"BUF-12: reset(scheduleForRound(N)) drives the rotated wave order",
		function()
			-- Multi-round drive: same director runs round 1 then resets
			-- with round 2's schedule and fires its rotated waves. This
			-- mirrors what RunController does between wave phases.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new()
			director:resume()

			local fired: { string } = {}
			director:onWave(function(hero: string)
				table.insert(fired, hero)
			end)

			director:tick(0)
			director:tick(12)
			director:tick(12)
			expect.truthy(director:isFinished(), "round 1 finished")

			director:reset(WaveDirector.scheduleForRound(2))
			expect.falsy(director:isFinished(), "fresh after reset")
			director:resume()

			director:tick(0)
			expect.eq(fired[#fired], "Buffalo", "round 2 leads with Buffalo")
			director:tick(12)
			expect.eq(fired[#fired], "Fox")
			director:tick(12)
			expect.eq(fired[#fired], "Goose")
			expect.truthy(director:isFinished(), "round 2 finished")
		end,
	},
	{
		"BUF-9: unoccupied heroes skip activation but still advance the cursor",
		function()
			-- Partial-lobby contract: when only some heroes are filled,
			-- waves targeting empty sectors must NOT fire (no enemies into
			-- undefended cores) but the schedule still progresses so the
			-- round can finish.
			local WaveDirector = loadDirector()
			local director = WaveDirector.new(sampleSchedule())
			director:resume()
			director:setHeroOccupancyResolver(function(heroId: string): boolean
				return heroId == "Fox" -- 1-player lobby with Fox only
			end)

			local fired: { string } = {}
			director:onWave(function(hero: string)
				table.insert(fired, hero)
			end)

			director:tick(0) -- Fox: occupied → fires
			expect.eq(#fired, 1)
			expect.eq(fired[1], "Fox")

			director:tick(12) -- Goose: unoccupied → skip
			expect.eq(#fired, 1, "Goose wave skipped")

			director:tick(12) -- Buffalo: unoccupied → skip
			expect.eq(#fired, 1, "Buffalo wave skipped")

			expect.truthy(director:isFinished(), "schedule still finishes through skips")
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
