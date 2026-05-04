--!strict
-- BUF-89: Spawn N enemies of a given type into a hero's sector.
-- v0.1 enemies are minimal R6 rigs (HumanoidRootPart + Torso + Humanoid)
-- that path toward the target sector's core via Humanoid:MoveTo. No
-- PathfindingService — the lane is a straight floor, naive movement is
-- enough.
--
-- Formation hints adjust spawn placement loosely:
--   loosePack: scattered across the spawn line (default)
--   tightPack: bunched in a narrow line near the lane center
--   backline:  scattered AND pushed farther back from the core
--
-- Cleanup: on Humanoid.Died OR on reaching the core, the enemy model is
-- destroyed. Core damage is a later issue; for now reaching the core is
-- just a despawn so they don't pile up on top of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sectors = require(ReplicatedStorage.Data.Sectors)
local Enemies = require(ReplicatedStorage.Waves.Enemies)

export type Formation = "loosePack" | "tightPack" | "backline"

type EnemySpec = {
	name: string,
	health: number,
	walkSpeed: number,
	size: Vector3,
	color: Color3,
}

type SectorLayout = {
	center: Vector3,
	floorColor: Color3,
	coreColor: Color3,
}

local WaveSpawner = {}

local random = Random.new()

-- Margins picked so the largest enemy (tank, ~3.5 deep) stays on the
-- sector floor even with the per-enemy Z jitter applied below.
local SPAWN_EDGE_MARGIN = 8
local BACKLINE_PUSHBACK = 4
local LATERAL_MARGIN = 6
local TIGHT_LANE_WIDTH = 6

-- Anchor for the wave: the sector edge opposite the core. Sign of
-- coreOffset.Z tells us which side of the sector the core is on; spawn on
-- the other side so enemies have a lane to march down.
local function spawnAnchorFor(sector: SectorLayout, formation: string?): Vector3
	local center = sector.center
	local coreSign = if Sectors.coreOffset.Z >= 0 then 1 else -1
	local edgeZ = center.Z - coreSign * (Sectors.SECTOR_DEPTH / 2 - SPAWN_EDGE_MARGIN)
	local backOffset = if formation == "backline" then -coreSign * BACKLINE_PUSHBACK else 0
	return Vector3.new(center.X, center.Y, edgeZ + backOffset)
end

-- Per-enemy offset from the spawn anchor.
local function offsetFor(formation: string?, index: number, count: number): Vector3
	if formation == "tightPack" then
		local denom = math.max(count, 1)
		local x = ((index - 1) - (count - 1) / 2) * (TIGHT_LANE_WIDTH / denom)
		return Vector3.new(x, 0, random:NextNumber(-1, 1))
	end
	-- loosePack and backline both scatter across the lane width. backline
	-- already shifted the anchor back; loose just hugs the spawn line.
	local halfWidth = Sectors.SECTOR_WIDTH / 2 - LATERAL_MARGIN
	return Vector3.new(
		random:NextNumber(-halfWidth, halfWidth),
		0,
		random:NextNumber(-2, 2)
	)
end

local function getCorePosition(heroId: string): Vector3?
	local sectorsFolder = Workspace:FindFirstChild("Sectors")
	if not sectorsFolder then return nil end
	local sectorFolder = sectorsFolder:FindFirstChild(heroId)
	if not sectorFolder then return nil end
	local core = sectorFolder:FindFirstChild("Core")
	if not core or not core:IsA("Model") then return nil end
	if core.PrimaryPart then
		return core.PrimaryPart.Position
	end
	return nil
end

local function getEnemiesContainer(): Folder
	local existing = Workspace:FindFirstChild("Enemies")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	return folder
end

-- Builds a minimal R6 NPC: a visible Torso welded to a small invisible
-- HumanoidRootPart. A rig-less Humanoid stays in FallingDown (see the note
-- in WorldBuilder for the Core), so we keep the Torso/RootJoint pair to
-- transition into Running.
local function buildEnemyModel(spec: EnemySpec, footPosition: Vector3): Model
	local model = Instance.new("Model")
	model.Name = spec.name

	local centerY = footPosition.Y + spec.size.Y / 2

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = spec.size
	torso.Color = spec.color
	torso.Material = Enum.Material.Plastic
	torso.Anchored = false
	torso.CanCollide = true
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Position = Vector3.new(footPosition.X, centerY, footPosition.Z)
	torso.Parent = model

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.Anchored = false
	hrp.CanCollide = false
	hrp.Massless = true
	hrp.Position = torso.Position
	hrp.Parent = model
	model.PrimaryPart = hrp

	local rootJoint = Instance.new("Weld")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = hrp
	rootJoint.Part1 = torso
	rootJoint.Parent = hrp

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = spec.health
	humanoid.Health = spec.health
	humanoid.WalkSpeed = spec.walkSpeed
	humanoid.HipHeight = 0
	humanoid.JumpPower = 0
	humanoid.AutoJumpEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayName = spec.name
	humanoid.Parent = model

	return model
end

-- Drive the enemy toward `corePos`. Humanoid:MoveTo has an 8s internal
-- timeout, so re-issue when MoveToFinished reports failure. Stop and clean
-- up on success or if the model has already been despawned (death path).
local function navigate(model: Model, humanoid: Humanoid, corePos: Vector3)
	local connection: RBXScriptConnection?
	connection = humanoid.MoveToFinished:Connect(function(reached: boolean)
		if not model.Parent or humanoid.Health <= 0 then
			if connection then connection:Disconnect() end
			return
		end
		if reached then
			if connection then connection:Disconnect() end
			model:Destroy()
			return
		end
		humanoid:MoveTo(corePos)
	end)
	humanoid:MoveTo(corePos)
end

function WaveSpawner.spawn(heroId: string, enemyType: string, count: number, formation: string?): { Model }
	local sector = Sectors.byHero[heroId]
	if not sector then
		warn(string.format("[WaveSpawner] Unknown heroId %q", heroId))
		return {}
	end
	local spec = Enemies[enemyType]
	if not spec then
		warn(string.format("[WaveSpawner] Unknown enemyType %q", enemyType))
		return {}
	end
	local corePos = getCorePosition(heroId)
	if not corePos then
		warn(string.format("[WaveSpawner] No Core in sector %q (build the world first)", heroId))
		return {}
	end

	local container = getEnemiesContainer()
	local anchor = spawnAnchorFor(sector, formation)
	local floorTopY = anchor.Y + Sectors.FLOOR_THICKNESS
	local spawned: { Model } = {}

	for i = 1, count do
		local off = offsetFor(formation, i, count)
		local foot = Vector3.new(anchor.X + off.X, floorTopY, anchor.Z + off.Z)
		local model = buildEnemyModel(spec, foot)
		model.Parent = container

		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.Died:Once(function()
			model:Destroy()
		end)

		task.spawn(navigate, model, humanoid, corePos)
		table.insert(spawned, model)
	end

	return spawned
end

return WaveSpawner
