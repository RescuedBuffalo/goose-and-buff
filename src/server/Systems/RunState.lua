--!strict
-- BUF-90: Track win/loss for a v0.1 run.
--   Loss: any sector core HP <= 0 (bound via :bindCore), OR every
--         registered hero is simultaneously down (BUF-11). The "every
--         hero down" path uses any opaque key (typically a Player) so
--         the same module is testable without Roblox types.
--   Win:  set externally via :setResult("win") once the round flow
--         (BUF-92's RunController) has finished all rounds.
--
-- Fires "win" or "loss" exactly once. Subsequent transitions are no-ops.
--
-- BUF-92: the single-round win check (director:isFinished + Enemies
-- empty) used to live here. With multi-round runs that condition is
-- per-round, not per-run, so it moved into RunController. This module
-- now does one thing: latch the first terminal result and notify.

export type Result = "win" | "loss"
export type ResultCallback = (Result) -> ()

local RunState = {}
RunState.__index = RunState

export type RunState = typeof(setmetatable(
	{} :: {
		_state: "running" | Result,
		_callbacks: { ResultCallback },
		-- BUF-11: per-hero alive map. true = up, false = down.
		-- Spectators / unoccupied slots never enter this map, so
		-- they don't pull the run into a loss when none are present.
		_aliveHeroes: { [any]: boolean },
		_heroCount: number,
	},
	RunState
))

function RunState.new(): RunState
	return setmetatable({
		_state = "running",
		_callbacks = {},
		_aliveHeroes = {},
		_heroCount = 0,
	}, RunState)
end

local function fire(self: RunState, result: Result)
	if self._state ~= "running" then
		return
	end
	self._state = result
	-- Spawn each callback so a slow listener can't block the others.
	for _, cb in ipairs(self._callbacks) do
		task.spawn(cb, result)
	end
end

function RunState.onResult(self: RunState, callback: ResultCallback)
	if self._state ~= "running" then
		task.spawn(callback, self._state :: Result)
		return
	end
	table.insert(self._callbacks, callback)
end

function RunState.bindCore(self: RunState, humanoid: Humanoid)
	humanoid.HealthChanged:Connect(function(health: number)
		if health <= 0 then
			fire(self, "loss")
		end
	end)
end

-- BUF-11: hero alive-state tracking.
-- registerHero adds the player as alive. Calls are idempotent — re-registering
-- a player who is already up is a no-op, so a respawn flow that re-runs
-- applyHero on rejoin doesn't double-count.
function RunState.registerHero(self: RunState, key: any)
	if self._aliveHeroes[key] ~= nil then
		return
	end
	self._aliveHeroes[key] = true
	self._heroCount += 1
end

local function checkAllDown(self: RunState)
	if self._heroCount <= 0 then
		return
	end
	for _, alive in pairs(self._aliveHeroes) do
		if alive then
			return
		end
	end
	fire(self, "loss")
end

-- unregisterHero is for permanent removal (player leaves). Use markHeroDown
-- for transient death+respawn cycles so the loss check sees the hero as
-- down rather than absent. Re-evaluates all-down on the way out: if the
-- leaver was the only remaining alive hero, the survivors are all down
-- and the run must resolve to defeat — there's no future markHeroDown
-- event coming to retrigger the check.
function RunState.unregisterHero(self: RunState, key: any)
	if self._aliveHeroes[key] == nil then
		return
	end
	self._aliveHeroes[key] = nil
	self._heroCount -= 1
	checkAllDown(self)
end

function RunState.markHeroDown(self: RunState, key: any)
	if self._aliveHeroes[key] == nil then
		return
	end
	self._aliveHeroes[key] = false
	checkAllDown(self)
end

function RunState.markHeroUp(self: RunState, key: any)
	if self._aliveHeroes[key] == nil then
		return
	end
	self._aliveHeroes[key] = true
end

-- BUF-92: external write path. RunController calls this after the
-- final round's wave clears so we converge on the same onResult fan-out
-- regardless of whether the run ended in a win or a loss.
function RunState.setResult(self: RunState, result: Result)
	fire(self, result)
end

function RunState.result(self: RunState): Result?
	if self._state == "running" then
		return nil
	end
	return self._state :: Result
end

return RunState
