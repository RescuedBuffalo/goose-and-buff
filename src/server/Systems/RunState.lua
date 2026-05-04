--!strict
-- BUF-90: Track win/loss for a v0.1 run.
--   Loss: any sector core HP <= 0 (bound via :bindCore).
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
	},
	RunState
))

function RunState.new(): RunState
	return setmetatable({
		_state = "running",
		_callbacks = {},
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
