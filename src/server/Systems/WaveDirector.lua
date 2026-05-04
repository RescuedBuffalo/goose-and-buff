--!strict
-- BUF-88: Heartbeat-driven wave scheduler.
-- Round 1 schedule per the v0.1 spec: Fox @ 0s, Goose @ 12s, Buffalo @ 24s.
-- Pure scheduler: it announces waves through a callback. Hooking the callback
-- to actual enemy spawning belongs to a later issue (BUF-7 run flow).

local RunService = game:GetService("RunService")

export type Wave = { time: number, hero: string }
export type WaveCallback = (hero: string, elapsed: number) -> ()

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
	},
	WaveDirector
))

local ROUND_1_SCHEDULE: { Wave } = {
	{ time = 0, hero = "Fox" },
	{ time = 12, hero = "Goose" },
	{ time = 24, hero = "Buffalo" },
}

function WaveDirector.new(schedule: { Wave }?): WaveDirector
	local self = setmetatable({
		_elapsed = 0,
		_nextIndex = 1,
		_schedule = schedule or ROUND_1_SCHEDULE,
		-- Start paused so callers can register :onWave before the first tick.
		_paused = true,
		_connection = nil,
		_onWave = nil,
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

function WaveDirector.tick(self: WaveDirector, dt: number)
	if self._paused then
		return
	end
	self._elapsed += dt
	while self._nextIndex <= #self._schedule
		and self._elapsed >= self._schedule[self._nextIndex].time
	do
		local wave = self._schedule[self._nextIndex]
		self._nextIndex += 1
		local cb = self._onWave
		if cb then
			cb(wave.hero, self._elapsed)
		end
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

return WaveDirector
