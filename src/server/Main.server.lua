--!strict
-- BUF-87: Player join → hero assignment → spawn in sector.
-- First 3 players get Goose / Buffalo / Fox in order. 4th+ go to spectator.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Heroes = require(ReplicatedStorage.Data.Heroes)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldBuilder = require(ServerScriptService.Adapters.WorldBuilder)
local WaveSpawner = require(ServerScriptService.Adapters.WaveSpawner)

-- Build the arena before wiring player handlers so spawn pads and the
-- spectator zone exist by the time anyone joins.
WorldBuilder.build()

-- We control the first spawn ourselves so the character never appears at the
-- default SpawnLocation before being teleported into a sector. Respawns after
-- death are handled by the Died hook below (delayed by Players.RespawnTime).
Players.CharacterAutoLoads = false

local heroByPlayer: { [Player]: string } = {}
local takenHeroes: { [string]: boolean } = {}
-- Guards the connect-then-iterate window: a player who joins between
-- PlayerAdded:Connect and the GetPlayers() catch-up pass would otherwise
-- be processed twice.
local seenPlayers: { [Player]: boolean } = {}

local function nextAvailableHero(): string?
	for _, heroId in ipairs(Constants.HEROES) do
		if not takenHeroes[heroId] then
			return heroId
		end
	end
	return nil
end

local function findSpawnPad(heroId: string): BasePart?
	local sectors = Workspace:FindFirstChild("Sectors")
	if not sectors then
		return nil
	end
	local sector = sectors:FindFirstChild(heroId)
	if not sector then
		return nil
	end
	local pad = sector:FindFirstChild("SpawnPad")
	if pad and pad:IsA("BasePart") then
		return pad
	end
	return nil
end

local function findSpectatorPad(): BasePart?
	local pad = Workspace:FindFirstChild("SpectatorZone")
	if pad and pad:IsA("BasePart") then
		return pad
	end
	return nil
end

local function teleportToPad(character: Model, pad: BasePart)
	-- Spawn slightly above the pad so we don't intersect it.
	local offset = CFrame.new(0, pad.Size.Y / 2 + 4, 0)
	character:PivotTo(pad.CFrame * offset)
end

local function bindRespawn(player: Player, humanoid: Humanoid)
	humanoid.Died:Once(function()
		task.wait(Players.RespawnTime)
		if player.Parent == Players then
			player:LoadCharacter()
		end
	end)
end

local function applyHero(player: Player, heroId: string)
	local hero = Heroes[heroId]
	if not hero then
		warn(string.format("[Main] No hero data for %q", heroId))
		return
	end

	heroByPlayer[player] = heroId
	takenHeroes[heroId] = true

	player.CharacterAdded:Connect(function(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.MaxHealth = hero.baseHealth
		humanoid.Health = hero.baseHealth
		humanoid.WalkSpeed = hero.moveSpeed
		-- DisplayName on the Humanoid is what shows on the in-world nametag.
		humanoid.DisplayName = hero.name

		local pad = findSpawnPad(heroId)
		if pad then
			character:WaitForChild("HumanoidRootPart")
			teleportToPad(character, pad)
		else
			warn(string.format("[Main] Missing Workspace.Sectors.%s.SpawnPad", heroId))
		end

		bindRespawn(player, humanoid)
	end)

	player:LoadCharacter()
end

local function sendToSpectator(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local pad = findSpectatorPad()
		if pad then
			character:WaitForChild("HumanoidRootPart")
			teleportToPad(character, pad)
		else
			warn("[Main] Late joiner with no SpectatorZone — leaving at default spawn")
		end

		bindRespawn(player, humanoid)
	end)

	player:LoadCharacter()
end

local function onPlayerJoined(player: Player)
	if seenPlayers[player] then return end
	seenPlayers[player] = true

	local heroId = nextAvailableHero()
	if heroId then
		applyHero(player, heroId)
	else
		sendToSpectator(player)
	end
end

Players.PlayerAdded:Connect(onPlayerJoined)

-- Catch any players already present when this script started (e.g. if
-- a long-running require elsewhere delayed our boot past the first join).
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerJoined(player)
end

Players.PlayerRemoving:Connect(function(player)
	seenPlayers[player] = nil
	local heroId = heroByPlayer[player]
	if heroId then
		takenHeroes[heroId] = nil
		heroByPlayer[player] = nil
	end
end)

-- BUF-89 smoke test: spawn one wave per sector after the world is built so
-- enemies walking to cores is visually verifiable in Studio. Remove when
-- the WaveDirector (BUF-88) is wired into WaveSpawner via the run lifecycle.
task.delay(5, function()
	WaveSpawner.spawn("Goose", "grunt", 4, "loosePack")
	WaveSpawner.spawn("Buffalo", "tank", 2, "tightPack")
	WaveSpawner.spawn("Fox", "runner", 6, "backline")
end)
