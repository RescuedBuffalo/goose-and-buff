--!strict
-- BUF-86: Build the v0.1 arena from Sectors data.
-- Three colored sector floors with cores (Humanoid for HP), spawn pads,
-- dividers between sectors, and a spectator zone.
--
-- Idempotent: tears down prior geometry before rebuilding so dev iteration
-- (hot-reload, manual rebuilds) doesn't stack copies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sectors = require(ReplicatedStorage.Data.Sectors)

local WorldBuilder = {}

local function makeAnchoredPart(name: string, props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function buildSector(heroId: string, layout): Folder
	local sector = Instance.new("Folder")
	sector.Name = heroId

	local center = layout.center
	local floorY = center.Y + Sectors.FLOOR_THICKNESS / 2

	makeAnchoredPart("Floor", {
		Size = Vector3.new(Sectors.SECTOR_WIDTH, Sectors.FLOOR_THICKNESS, Sectors.SECTOR_DEPTH),
		Position = Vector3.new(center.X, floorY, center.Z),
		Color = layout.floorColor,
		Material = Enum.Material.SmoothPlastic,
	}, sector)

	-- SpawnPad: matches the path BUF-87's Main.server.lua already reads.
	local padOffset = Sectors.spawnPadOffset
	makeAnchoredPart("SpawnPad", {
		Size = Sectors.spawnPadSize,
		Position = Vector3.new(
			center.X + padOffset.X,
			center.Y + Sectors.FLOOR_THICKNESS + Sectors.spawnPadSize.Y / 2,
			center.Z + padOffset.Z
		),
		Color = layout.coreColor,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	}, sector)

	-- Core: a Model with a HumanoidRootPart and a Humanoid for HP.
	-- BUF-4/BUF-5 will read Core.Humanoid.Health for the lose condition.
	local coreModel = Instance.new("Model")
	coreModel.Name = "Core"

	local coreOffset = Sectors.coreOffset
	local hrp = makeAnchoredPart("HumanoidRootPart", {
		Size = Sectors.coreSize,
		Position = Vector3.new(
			center.X + coreOffset.X,
			center.Y + Sectors.FLOOR_THICKNESS + Sectors.coreSize.Y / 2,
			center.Z + coreOffset.Z
		),
		Color = layout.coreColor,
		Material = Enum.Material.Neon,
	}, coreModel)
	coreModel.PrimaryPart = hrp

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = Sectors.coreHealth
	humanoid.Health = Sectors.coreHealth
	humanoid.DisplayName = heroId .. " Core"
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.Parent = coreModel

	-- Contract: the Core uses Humanoid as an HP container (per BUF-86 ACs).
	-- It does NOT fire Humanoid.Died — Roblox locks anchored, rig-less
	-- Humanoids in FallingDown and rejects the Dead transition. BUF-4/BUF-5
	-- should listen to Humanoid.HealthChanged and treat health <= 0 as
	-- destruction.

	coreModel.Parent = sector
	return sector
end

local function buildDividers(parent: Folder)
	local dividers = Instance.new("Folder")
	dividers.Name = "Dividers"

	for i = 1, #Sectors.order - 1 do
		local left = Sectors.byHero[Sectors.order[i]]
		local right = Sectors.byHero[Sectors.order[i + 1]]
		local midX = (left.center.X + right.center.X) / 2
		makeAnchoredPart(
			"Wall_" .. Sectors.order[i] .. "_" .. Sectors.order[i + 1],
			{
				Size = Vector3.new(Sectors.WALL_THICKNESS, Sectors.WALL_HEIGHT, Sectors.SECTOR_DEPTH),
				Position = Vector3.new(midX, Sectors.FLOOR_THICKNESS + Sectors.WALL_HEIGHT / 2, 0),
				Color = Sectors.dividerColor,
				Material = Enum.Material.Slate,
			},
			dividers
		)
	end

	dividers.Parent = parent
end

local function buildSpectator()
	local sz = Sectors.spectator
	makeAnchoredPart("SpectatorZone", {
		Size = sz.size,
		Position = Vector3.new(sz.center.X, sz.center.Y + sz.size.Y / 2, sz.center.Z),
		Color = sz.color,
		Material = Enum.Material.SmoothPlastic,
	}, Workspace)
end

local function tearDown()
	for _, name in ipairs({ "Sectors", "SpectatorZone" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then existing:Destroy() end
	end
end

function WorldBuilder.build()
	tearDown()

	-- Build the whole tree off-Workspace, then parent atomically so any
	-- consumer doing Workspace:WaitForChild("Sectors") sees a complete tree.
	local sectorsFolder = Instance.new("Folder")
	sectorsFolder.Name = "Sectors"
	for _, heroId in ipairs(Sectors.order) do
		local s = buildSector(heroId, Sectors.byHero[heroId])
		s.Parent = sectorsFolder
	end
	buildDividers(sectorsFolder)
	sectorsFolder.Parent = Workspace

	buildSpectator()

	print("[WorldBuilder] Arena built: " .. table.concat(Sectors.order, ", "))
end

return WorldBuilder
