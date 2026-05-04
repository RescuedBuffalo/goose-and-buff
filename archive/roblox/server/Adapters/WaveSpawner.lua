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
-- Cleanup:
--   on Humanoid.Died:        model is destroyed
--   on reaching the core:    core's Humanoid takes spec.damage, model
--                            is destroyed (BUF-90 added the damage step)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sectors = require(ReplicatedStorage.Data.Sectors)
local Enemies = require(ReplicatedStorage.Waves.Enemies)

export type Formation = "loosePack" | "tightPack" | "backline"

type EnemySpec = {
	name: string,
	health: number,
	walkSpeed: number,
	damage: number,
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

local function getCoreModel(heroId: string): Model?
	local sectorsFolder = Workspace:FindFirstChild("Sectors")
	if not sectorsFolder then return nil end
	local sectorFolder = sectorsFolder:FindFirstChild(heroId)
	if not sectorFolder then return nil end
	local core = sectorFolder:FindFirstChild("Core")
	if not core or not core:IsA("Model") then return nil end
	return core
end

local CORE_APPROACH_BUFFER = 2

-- The MoveTo target: a point a couple studs in front of the core's near
-- face on the enemy's approach side. We can't aim at the core's center —
-- the Core is a collidable 8x8x8 Part, so the enemy's torso physically
-- can't get within MoveTo's ~2-stud proximity threshold of it. That would
-- make MoveToFinished always report `reached=false` and the navigate
-- retry loop run forever, piling enemies up at the boundary.
local function approachTargetFor(corePos: Vector3): Vector3
	local coreSign = if Sectors.coreOffset.Z >= 0 then 1 else -1
	local approachZ = -coreSign * (Sectors.coreSize.Z / 2 + CORE_APPROACH_BUFFER)
	return corePos + Vector3.new(0, 0, approachZ)
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
	-- HRP overlaps the Torso. CanQuery=false so a player's mouse raycast
	-- (and the ClickDetector pick) lands on the visible Torso, not the
	-- invisible root.
	hrp.CanQuery = false
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

-- Drive the enemy toward `target`. Humanoid:MoveTo has an 8s internal
-- timeout, so re-issue when MoveToFinished reports failure. On a successful
-- reach, deal `damage` to the core's Humanoid and despawn. The core
-- humanoid may already be dead by the time we arrive (RunState fires
-- "loss" the moment any core hits 0), in which case we skip the damage
-- step and just despawn.
local function navigate(
	model: Model,
	humanoid: Humanoid,
	target: Vector3,
	coreHumanoid: Humanoid?,
	damage: number
)
	local connection: RBXScriptConnection?
	connection = humanoid.MoveToFinished:Connect(function(reached: boolean)
		if not model.Parent or humanoid.Health <= 0 then
			if connection then connection:Disconnect() end
			return
		end
		if reached then
			if connection then connection:Disconnect() end
			if coreHumanoid and coreHumanoid.Parent and coreHumanoid.Health > 0 then
				coreHumanoid:TakeDamage(damage)
			end
			model:Destroy()
			return
		end
		humanoid:MoveTo(target)
	end)
	humanoid:MoveTo(target)
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
	local coreModel = getCoreModel(heroId)
	if not coreModel or not coreModel.PrimaryPart then
		warn(string.format("[WaveSpawner] No Core in sector %q (build the world first)", heroId))
		return {}
	end
	local target = approachTargetFor(coreModel.PrimaryPart.Position)
	local coreHumanoid = coreModel:FindFirstChildOfClass("Humanoid")

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

		task.spawn(navigate, model, humanoid, target, coreHumanoid, spec.damage)
		table.insert(spawned, model)
	end

	return spawned
end

return WaveSpawner
