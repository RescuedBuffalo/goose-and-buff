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

-- BUF-90: world-space HP bar above a core. Updates on HealthChanged and
-- shifts color green -> yellow -> red as health drops.
local function attachCoreHpBar(heroId: string, hrp: BasePart, humanoid: Humanoid)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HpBar"
	billboard.Size = UDim2.new(0, 220, 0, 36)
	billboard.StudsOffset = Vector3.new(0, hrp.Size.Y / 2 + 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = hrp

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = bg

	local function update()
		local maxH = humanoid.MaxHealth
		local cur = math.max(0, humanoid.Health)
		local pct = if maxH > 0 then cur / maxH else 0
		fill.Size = UDim2.new(pct, 0, 1, 0)
		if pct < 0.3 then
			fill.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
		elseif pct < 0.6 then
			fill.BackgroundColor3 = Color3.fromRGB(220, 200, 80)
		else
			fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
		end
		label.Text = string.format("%s Core: %d / %d", heroId, cur, maxH)
	end

	update()
	humanoid.HealthChanged:Connect(update)
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
	-- Humanoids in FallingDown and rejects the Dead transition. BUF-90's
	-- RunState listens to Humanoid.HealthChanged and treats health <= 0
	-- as a run loss.

	attachCoreHpBar(heroId, hrp, humanoid)

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
	for _, name in ipairs({ "Sectors", "SpectatorZone", "RunResult" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then existing:Destroy() end
	end
end

-- BUF-90 / BUF-92: world-space banner above the arena, mirroring the
-- run end screen the client renders. Copy matches BUF-92's spec: "RUN
-- COMPLETE — VICTORY" on win, "RUN ENDED — DEFEAT" on loss. Replaces
-- any prior result banner so a re-run can re-announce.
function WorldBuilder.showResult(result: "win" | "loss")
	local existing = Workspace:FindFirstChild("RunResult")
	if existing then existing:Destroy() end

	local part = Instance.new("Part")
	part.Name = "RunResult"
	part.Size = Vector3.new(40, 8, 1)
	part.Position = Vector3.new(0, 30, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 600, 0, 200)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = if result == "win"
		then Color3.fromRGB(60, 160, 60)
		else Color3.fromRGB(160, 60, 60)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = if result == "win"
		then "RUN COMPLETE — VICTORY"
		else "RUN ENDED — DEFEAT"
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = billboard
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
