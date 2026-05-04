--!strict
-- BUF-88: Heartbeat-driven wave scheduler.
-- BUF-91: Per-player visibility (`getVisibleStateForPlayer`) for the
-- first-hit info reveal — the spine mechanic. Only the targeted player
-- sees the composition; teammates see redacted "in combat" status.
--
-- Round 1 schedule per the v0.1 spec: Fox @ 0s, Goose @ 12s, Buffalo @ 24s.
-- Wave compositions live in shared/Data/Waves.lua (pure data).
--
-- Without a real "wave cleared" signal yet (BUF-7 owns the run lifecycle),
-- we auto-expire active waves after WAVE_VISIBILITY_SECONDS so the reveal
-- panel doesn't get stuck on screen forever. BUF-7 should swap auto-expiry
-- for explicit `:endWave(hero)` calls when enemies are downed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Waves = require(ReplicatedStorage.Data.Waves)

export type Wave = { time: number, hero: string }
export type WaveCallback = (hero: string, elapsed: number) -> ()
export type StateChangedCallback = () -> ()

export type EnemyComposition = Waves.EnemyComposition
export type WaveComposition = Waves.WaveComposition

-- One active wave's runtime state on the server.
type ActiveWave = {
	hero: string,
	composition: WaveComposition,
	startedAt: number,
	expiresAt: number,
}

-- Per-player teammate row in the visible state.
export type TeammateView = {
	heroId: string,
	name: string,
	inCombat: boolean,
	coreHp: number,
	coreMaxHp: number,
}

-- Full per-player visible state. `composition` is non-nil only for the
-- first-hit player on an active wave; teammates' rows never include it.
export type PlayerView = {
	selfHeroId: string?,
	selfInCombat: boolean,
	composition: WaveComposition?,
	teammates: { TeammateView },
}

export type CoreInfo = { hp: number, maxHp: number }
export type HeroResolver = (Player) -> string?
export type CoreInfoResolver = (string) -> CoreInfo?
export type HeroOccupancyResolver = (string) -> boolean

-- How long the reveal panel stays up after a wave fires, in seconds.
-- v0.1 stub: BUF-7 will replace with explicit "wave cleared" events.
local WAVE_VISIBILITY_SECONDS = 10

local WaveDirector = {}
WaveDirector.__index = WaveDirector

export type WaveDirector = typeof(setmetatable(
	{} :: {
		_elapsed: number,
		_nextIndex: number,
		_schedule: { Wave },
		_paused: boolean,
		_connection: RBXScriptConnection?,
		_onWave: WaveCallback?,
		_onStateChanged: StateChangedCallback?,
		_active: { [string]: ActiveWave },
		_heroResolver: HeroResolver?,
		_coreInfoResolver: CoreInfoResolver?,
		_heroOccupancyResolver: HeroOccupancyResolver?,
		_allHeroes: { string },
	},
	WaveDirector
))

local ROUND_1_SCHEDULE: { Wave } = {
	{ time = 0, hero = "Fox" },
	{ time = 12, hero = "Goose" },
	{ time = 24, hero = "Buffalo" },
}

local function collectHeroesFromSchedule(schedule: { Wave }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, wave in ipairs(schedule) do
		if not seen[wave.hero] then
			seen[wave.hero] = true
			table.insert(out, wave.hero)
		end
	end
	return out
end

function WaveDirector.new(schedule: { Wave }?): WaveDirector
	local sched = schedule or ROUND_1_SCHEDULE
	local self = setmetatable({
		_elapsed = 0,
		_nextIndex = 1,
		_schedule = sched,
		-- Start paused so callers can register :onWave before the first tick.
		_paused = true,
		_connection = nil,
		_onWave = nil,
		_onStateChanged = nil,
		_active = {},
		_heroResolver = nil,
		_coreInfoResolver = nil,
		_heroOccupancyResolver = nil,
		_allHeroes = collectHeroesFromSchedule(sched),
	}, WaveDirector)
	return self
end

function WaveDirector.round1Schedule(): { Wave }
	-- Defensive copy so callers can't mutate the canonical schedule.
	local copy = table.create(#ROUND_1_SCHEDULE)
	for i, wave in ipairs(ROUND_1_SCHEDULE) do
		copy[i] = { time = wave.time, hero = wave.hero }
	end
	return copy
end

function WaveDirector.onWave(self: WaveDirector, callback: WaveCallback)
	self._onWave = callback
end

-- Fired whenever the active-wave set changes (wave starts or expires). Used
-- by the broadcaster to re-send PlayerView to each client. Granular enough
-- that we don't push state every Heartbeat.
function WaveDirector.onStateChanged(self: WaveDirector, callback: StateChangedCallback)
	self._onStateChanged = callback
end

-- Resolvers let getVisibleStateForPlayer answer per-player questions
-- without WaveDirector owning player→hero mapping or core HP tracking.
function WaveDirector.setHeroResolver(self: WaveDirector, resolver: HeroResolver)
	self._heroResolver = resolver
end

function WaveDirector.setCoreInfoResolver(self: WaveDirector, resolver: CoreInfoResolver)
	self._coreInfoResolver = resolver
end

-- Optional. When set, teammate rows are filtered to heroes the resolver
-- reports as occupied (i.e., a player is currently bound to that hero).
-- Without it, all scheduled heroes are listed — fine for tests, wrong for
-- partial lobbies where empty slots would otherwise show phantom cards.
function WaveDirector.setHeroOccupancyResolver(self: WaveDirector, resolver: HeroOccupancyResolver)
	self._heroOccupancyResolver = resolver
end

local function fireStateChanged(self: WaveDirector)
	local cb = self._onStateChanged
	if cb then
		cb()
	end
end

local function activateWave(self: WaveDirector, hero: string, elapsed: number)
	local composition = Waves.byHero[hero]
	if not composition then
		warn(string.format("[WaveDirector] No composition for hero %q — skipping activation", hero))
		return
	end
	self._active[hero] = {
		hero = hero,
		composition = composition,
		startedAt = elapsed,
		expiresAt = elapsed + WAVE_VISIBILITY_SECONDS,
	}
end

local function expireDueWaves(self: WaveDirector): boolean
	local changed = false
	for hero, active in pairs(self._active) do
		if self._elapsed >= active.expiresAt then
			self._active[hero] = nil
			changed = true
		end
	end
	return changed
end

function WaveDirector.tick(self: WaveDirector, dt: number)
	if self._paused then
		return
	end
	self._elapsed += dt

	local stateChanged = expireDueWaves(self)

	while self._nextIndex <= #self._schedule
		and self._elapsed >= self._schedule[self._nextIndex].time
	do
		local wave = self._schedule[self._nextIndex]
		self._nextIndex += 1
		activateWave(self, wave.hero, self._elapsed)
		stateChanged = true
		local cb = self._onWave
		if cb then
			cb(wave.hero, self._elapsed)
		end
	end

	if stateChanged then
		fireStateChanged(self)
	end
end

function WaveDirector.start(self: WaveDirector)
	if self._connection then
		return
	end
	self._paused = false
	self._connection = RunService.Heartbeat:Connect(function(dt: number)
		self:tick(dt)
	end)
end

function WaveDirector.pause(self: WaveDirector)
	self._paused = true
end

function WaveDirector.resume(self: WaveDirector)
	self._paused = false
end

function WaveDirector.stop(self: WaveDirector)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self._paused = true
end

function WaveDirector.isFinished(self: WaveDirector): boolean
	return self._nextIndex > #self._schedule
end

function WaveDirector.elapsed(self: WaveDirector): number
	return self._elapsed
end

-- BUF-91 spine: returns the per-player view that respects info-reveal rules.
-- The targeted player gets `composition`; everyone else sees only redacted
-- teammate rows. Returns a stable shape even when resolvers aren't wired,
-- so the client renderer never has to special-case missing context.
function WaveDirector.getVisibleStateForPlayer(self: WaveDirector, player: Player): PlayerView
	local heroResolver = self._heroResolver
	local coreInfoResolver = self._coreInfoResolver
	local occupancyResolver = self._heroOccupancyResolver
	local selfHeroId: string? = if heroResolver then heroResolver(player) else nil

	local selfActive = if selfHeroId then self._active[selfHeroId] else nil

	local teammates: { TeammateView } = {}
	for _, heroId in ipairs(self._allHeroes) do
		if heroId ~= selfHeroId then
			-- Skip unoccupied slots so partial lobbies (1–2 players, mid-disconnect)
			-- don't render phantom teammate cards. With no resolver wired we keep
			-- the old "include all" default for tests.
			local occupied = if occupancyResolver then occupancyResolver(heroId) else true
			if occupied then
				local coreInfo = if coreInfoResolver then coreInfoResolver(heroId) else nil
				local hp = if coreInfo then coreInfo.hp else 0
				local maxHp = if coreInfo then coreInfo.maxHp else 0
				table.insert(teammates, {
					heroId = heroId,
					name = heroId,
					inCombat = self._active[heroId] ~= nil,
					coreHp = hp,
					coreMaxHp = maxHp,
				})
			end
		end
	end

	return {
		selfHeroId = selfHeroId,
		selfInCombat = selfActive ~= nil,
		composition = if selfActive then selfActive.composition else nil,
		teammates = teammates,
	}
end

return WaveDirector
