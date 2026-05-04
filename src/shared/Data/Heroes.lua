--!strict
-- Pure data: hero stats. No Roblox APIs.
-- Keys are heroIds used everywhere else (Constants.HEROES, sector names, nametags).

local Heroes = {
	Goose = {
		name = "Goose",
		baseHealth = 100,
		moveSpeed = 18,
	},
	Buffalo = {
		name = "Buffalo",
		baseHealth = 160,
		moveSpeed = 12,
	},
	Fox = {
		name = "Fox",
		baseHealth = 85,
		moveSpeed = 22,
	},
}

return Heroes
