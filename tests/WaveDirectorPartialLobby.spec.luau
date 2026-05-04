--!strict
-- Regression tests for the partial-lobby case.
-- Without an occupancy resolver the director "sees" every scheduled hero
-- as occupied (fine for tests, wrong for live). With a resolver wired,
-- teammate rows must drop unoccupied heroes so 1-2 player lobbies and
-- mid-disconnect states don't render phantom cards in the HUD.

local sandbox = require("./lib/sandbox")
local expect = require("./lib/expect")

local function loadDirector()
	local env = sandbox.makeEnv()
	return sandbox.loadModule("src/server/Systems/WaveDirector.lua", env)
end

local function buildDirector()
	local WaveDirector = loadDirector()
	return WaveDirector.new({
		{ time = 0, hero = "Fox" },
		{ time = 12, hero = "Goose" },
		{ time = 24, hero = "Buffalo" },
	})
end

return {
	{
		"no occupancy resolver: every other hero shows as a teammate (default)",
		function()
			-- Sanity check on the default — the test-friendly fallback so
			-- existing test fixtures don't all need to wire a resolver.
			local director = buildDirector()
			local player = newproxy(false)
			director:setHeroResolver(function(_p: any): string?
				return "Fox"
			end)

			local view = director:getVisibleStateForPlayer(player :: any)
			expect.eq(#view.teammates, 2, "Goose+Buffalo show by default")
		end,
	},
	{
		"occupancy resolver filters out unoccupied teammate slots",
		function()
			-- 1-player lobby: only Fox is occupied. Goose/Buffalo must
			-- not appear as teammates.
			local director = buildDirector()
			local player = newproxy(false)
			director:setHeroResolver(function(_p: any): string?
				return "Fox"
			end)
			director:setHeroOccupancyResolver(function(heroId: string): boolean
				return heroId == "Fox"
			end)

			local view = director:getVisibleStateForPlayer(player :: any)
			expect.eq(#view.teammates, 0, "no teammates in 1-player lobby")
		end,
	},
	{
		"partial lobby: 2 occupied heroes shows exactly one teammate row",
		function()
			-- 2-player lobby: Fox + Goose only. Goose's view should show
			-- Fox once, Buffalo not at all.
			local director = buildDirector()
			local player = newproxy(false)
			director:setHeroResolver(function(_p: any): string?
				return "Goose"
			end)
			director:setHeroOccupancyResolver(function(heroId: string): boolean
				return heroId == "Fox" or heroId == "Goose"
			end)

			local view = director:getVisibleStateForPlayer(player :: any)
			expect.eq(#view.teammates, 1, "exactly one teammate row")
			expect.eq(view.teammates[1].heroId, "Fox")

			local hasBuffalo = false
			for _, row in ipairs(view.teammates) do
				if row.heroId == "Buffalo" then
					hasBuffalo = true
				end
			end
			expect.falsy(hasBuffalo, "no phantom Buffalo card")
		end,
	},
	{
		"core info resolver returns nil: HUD still gets a stable shape (zeros)",
		function()
			-- Defensive contract: even with no resolver wired, the
			-- teammate row carries 0/0 HP rather than nils that would
			-- crash the renderer.
			local director = buildDirector()
			local player = newproxy(false)
			director:setHeroResolver(function(_p: any): string?
				return "Fox"
			end)
			director:setHeroOccupancyResolver(function(_h: string): boolean
				return true
			end)

			local view = director:getVisibleStateForPlayer(player :: any)
			expect.eq(#view.teammates, 2)
			for _, row in ipairs(view.teammates) do
				expect.eq(row.coreHp, 0, "coreHp default")
				expect.eq(row.coreMaxHp, 0, "coreMaxHp default")
			end
		end,
	},
}
