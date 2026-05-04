--!strict
-- BUF-87: Player join → hero assignment → spawn in sector.
-- BUF-91: Per-player StateUpdate broadcast so each client renders the
-- right view of an active wave (first-hit composition vs. teammate badge).
-- First 3 players get Goose / Buffalo / Fox in order. 4th+ go to spectator.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Heroes = require(ReplicatedStorage.Data.Heroes)
local Waves = require(ReplicatedStorage.Data.Waves)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldBuilder = require(ServerScriptService.Adapters.WorldBuilder)
local WaveSpawner = require(ServerScriptService.Adapters.WaveSpawner)
local WaveDirector = require(ServerScriptService.Systems.WaveDirector)
local Combat = require(ServerScriptService.Systems.Combat)
local RunState = require(ServerScriptService.Systems.RunState)

-- Build the arena before wiring player handlers so spawn pads and the
-- spectator zone exist by the time anyone joins.
WorldBuilder.build()

-- BUF-90: pre-create the Enemies folder so RunState can listen for
-- ChildRemoved from t=0. Without this, the folder appears lazily on the
-- first spawn and a listener attached at startup would miss it.
local enemiesFolder = Workspace:FindFirstChild("Enemies")
if not (enemiesFolder and enemiesFolder:IsA("Folder")) then
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = Workspace
end

local takenHeroes: { [string]: boolean } = {}
-- Guards the connect-then-iterate window: a player who joins between
-- PlayerAdded:Connect and the GetPlayers() catch-up pass would otherwise
-- be processed twice.
local seenPlayers: { [Player]: boolean } = {}
-- The (player -> heroId) registry lives in Combat (BUF-90), so the
-- click-damage path can resolve the clicker's hero without coupling back
-- to Main. BUF-91's WaveDirector resolver below also reads through Combat.

-- BUF-91: replicate per-player wave state. Created here so any client
-- :WaitForChild() resolves once Main has booted.
local stateUpdate = Instance.new("RemoteEvent")
stateUpdate.Name = Constants.REMOTES.StateUpdate
stateUpdate.Parent = ReplicatedStorage

local function findCoreHumanoid(heroId: string): Humanoid?
	local sectors = Workspace:FindFirstChild("Sectors")
	if not sectors then return nil end
	local sector = sectors:FindFirstChild(heroId)
	if not sector then return nil end
	local core = sector:FindFirstChild("Core")
	if not core then return nil end
	local humanoid = core:FindFirstChildOfClass("Humanoid")
	return humanoid
end

-- BUF-90: track win/loss and bind every core's HealthChanged into it.
local runState = RunState.new()
local sectorsFolder = Workspace:WaitForChild("Sectors")
for _, heroId in ipairs(Constants.HEROES) do
	local coreHumanoid = findCoreHumanoid(heroId)
	if coreHumanoid then
		runState:bindCore(coreHumanoid)
	else
		warn(string.format("[Main] No Core humanoid for %q — RunState won't see its loss", heroId))
	end
end

-- BUF-88 + BUF-89 + BUF-90 + BUF-91: stand up the Heartbeat-driven scheduler,
-- hand each announced wave to the spawner (binding ClickDetectors so heroes
-- can damage enemies), and let WaveDirector compute per-player visibility.
-- Wave compositions live in shared/Data/Waves.lua so the spawner and the
-- HUD reveal panel read from the same source of truth. Prep-phase pause
-- and end-of-run cleanup belong to the run lifecycle (BUF-7).
local director = WaveDirector.new()
director:onWave(function(hero, _elapsed)
	local wave = Waves.byHero[hero]
	if not wave then
		warn(string.format("[Main] No wave composition for hero %q", hero))
		return
	end
	for _, enemy in ipairs(wave.enemies) do
		local models = WaveSpawner.spawn(hero, enemy.type, enemy.count, enemy.formation)
		for _, model in ipairs(models) do
			local torso = model:FindFirstChild("Torso")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if torso and torso:IsA("BasePart") and humanoid then
				Combat.bindEnemyClicks(torso, humanoid)
			end
		end
	end
end)

-- BUF-91: feed WaveDirector the context it needs to compute per-player views.
-- Hero lookup goes through Combat (BUF-90's single source of truth) so we
-- don't keep a parallel registry in Main.
director:setHeroResolver(function(player: Player): string?
	return Combat.heroFor(player)
end)
director:setCoreInfoResolver(function(heroId: string)
	local humanoid = findCoreHumanoid(heroId)
	if not humanoid then return nil end
	return { hp = humanoid.Health, maxHp = humanoid.MaxHealth }
end)
director:setHeroOccupancyResolver(function(heroId: string)
	return takenHeroes[heroId] == true
end)

local function broadcastStateToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		stateUpdate:FireClient(player, director:getVisibleStateForPlayer(player))
	end
end

local function broadcastStateTo(player: Player)
	if player.Parent ~= Players then return end
	stateUpdate:FireClient(player, director:getVisibleStateForPlayer(player))
end

director:onStateChanged(broadcastStateToAll)

-- Client-driven handshake: the join-time FireClient below is best-effort
-- and is dropped if the client's CombatHud hasn't yet connected its
-- OnClientEvent (slow joins, late StarterPlayerScripts boot). The HUD
-- fires this event as soon as it's wired up, and we reply with a fresh
-- snapshot — guarantees every client gets at least one state regardless
-- of timing.
stateUpdate.OnServerEvent:Connect(function(player: Player)
	broadcastStateTo(player)
end)

-- Cores already exist (built above). Re-broadcast on HP change so teammate
-- portraits track damage. We don't need to disconnect — cores live for the
-- lifetime of the server.
for _, heroId in ipairs(Constants.HEROES) do
	local humanoid = findCoreHumanoid(heroId)
	if humanoid then
		humanoid.HealthChanged:Connect(broadcastStateToAll)
	end
end

director:start()

-- BUF-90: bind run win condition AFTER the director exists; cores are
-- already bound above. Result handler stops new waves, clears any in-flight
-- enemies, and shows the banner.
runState:bindRun(director, enemiesFolder :: Folder)
runState:onResult(function(result)
	director:stop()
	for _, child in ipairs((enemiesFolder :: Folder):GetChildren()) do
		child:Destroy()
	end
	WorldBuilder.showResult(result)
end)

game:BindToClose(function()
	director:stop()
end)

-- We control the first spawn ourselves so the character never appears at the
-- default SpawnLocation before being teleported into a sector. Respawns after
-- death are handled by the Died hook below (delayed by Players.RespawnTime).
Players.CharacterAutoLoads = false

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

	takenHeroes[heroId] = true
	Combat.bindPlayer(player, heroId)

	-- BUF-91: send initial state now that we know this player's hero, so the
	-- HUD can build its portraits before any wave fires.
	broadcastStateTo(player)

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
	-- BUF-91: spectators get a state with no selfHeroId so the HUD stays hidden.
	broadcastStateTo(player)

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
	local heroId = Combat.heroFor(player)
	if heroId then
		takenHeroes[heroId] = nil
		Combat.unbindPlayer(player)
		-- BUF-91: refresh remaining clients so the leaver's portrait drops out.
		broadcastStateToAll()
	end
end)
