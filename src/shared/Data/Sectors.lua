--!strict
-- Pure data: arena layout for v0.1. Read by Adapters.WorldBuilder.
-- Color values per the v0.1 spec ("color blocks beat textures").

local Sectors = {}

Sectors.SECTOR_WIDTH = 60
Sectors.SECTOR_DEPTH = 80
Sectors.WALL_THICKNESS = 2
Sectors.WALL_HEIGHT = 8
Sectors.FLOOR_THICKNESS = 1

-- Order is left-to-right along the X axis. Dividers go between consecutive entries.
Sectors.order = { "Goose", "Buffalo", "Fox" }

Sectors.byHero = {
	Goose = {
		center = Vector3.new(-62, 0, 0),
		floorColor = Color3.fromRGB(255, 248, 200),
		coreColor = Color3.fromRGB(255, 220, 80),
	},
	Buffalo = {
		center = Vector3.new(0, 0, 0),
		floorColor = Color3.fromRGB(150, 100, 70),
		coreColor = Color3.fromRGB(110, 70, 40),
	},
	Fox = {
		center = Vector3.new(62, 0, 0),
		floorColor = Color3.fromRGB(255, 180, 100),
		coreColor = Color3.fromRGB(220, 100, 30),
	},
}

-- Offsets within a sector, relative to its center.
Sectors.spawnPadOffset = Vector3.new(0, 0, -28)
Sectors.coreOffset = Vector3.new(0, 4, 28)

Sectors.spawnPadSize = Vector3.new(12, 1, 12)
Sectors.coreSize = Vector3.new(8, 8, 8)
Sectors.coreHealth = 1000

Sectors.dividerColor = Color3.fromRGB(60, 60, 60)

Sectors.spectator = {
	center = Vector3.new(0, 0, 80),
	size = Vector3.new(40, 1, 20),
	color = Color3.fromRGB(80, 80, 100),
}

return Sectors
