--!strict
-- Pure data: enemy stats for v0.1 wave spawning. Read by Adapters.WaveSpawner.
-- Color values per the v0.1 spec ("color blocks beat textures").
-- Keys are enemyType ids passed to WaveSpawner.spawn().

local Enemies = {
	grunt = {
		name = "Grunt",
		health = 50,
		walkSpeed = 8,
		size = Vector3.new(2, 4, 2),
		color = Color3.fromRGB(180, 60, 60),
	},
	runner = {
		name = "Runner",
		health = 25,
		walkSpeed = 16,
		size = Vector3.new(1.5, 3, 1.5),
		color = Color3.fromRGB(220, 140, 60),
	},
	tank = {
		name = "Tank",
		health = 200,
		walkSpeed = 5,
		size = Vector3.new(3.5, 5, 3.5),
		color = Color3.fromRGB(100, 60, 180),
	},
}

return Enemies
