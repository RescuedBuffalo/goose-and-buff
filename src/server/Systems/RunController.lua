--!strict
-- BUF-92: Round-flow state machine.
-- Stitches a run together: prep -> wave -> debrief, repeated TOTAL_ROUNDS
-- times. After the final round's wave clears, fires "win" via the bound
-- RunState. A "loss" fired by RunState (any core hits zero) cancels the
-- in-flight round and transitions to phase "defeat".
--
-- The controller broadcasts a RunStatus on every phase transition. The
-- prep / debrief deadlines use workspace:GetServerTimeNow() so clients
-- can compute remaining time locally without us flooding the network
-- with per-second ticks.
--
-- Wave-clear detection: each round ends when the bound director reports
-- isFinished AND the Enemies folder is empty. We poll on a 0.25s tick
-- rather than wiring ChildRemoved + onStateChanged here because the
-- polling loop also serves as the cancellation check (loss mid-wave).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

export type Phase = "prep" | "wave" | "debrief" | "victory" | "defeat"
export type Result = "win" | "loss"

export type RunStatus = {
	phase: Phase,
	round: number,
	totalRounds: number,
	-- workspace:GetServerTimeNow() at which the current timed phase
	-- (prep / debrief) ends. Nil for phases without a fixed duration.
	deadline: number?,
	result: Result?,
}

export type StatusCallback = (RunStatus) -> ()
export type RoundStartCallback = (number) -> ()

-- Structural types: avoid coupling to the concrete director / runState
-- modules so this controller is testable in isolation.
type Director = {
	reset: (Director, any?) -> (),
	start: (Director) -> (),
	stop: (Director) -> (),
	isFinished: (Director) -> boolean,
}

type RunState = {
	onResult: (RunState, (Result) -> ()) -> (),
	setResult: (RunState, Result) -> (),
}

local POLL_INTERVAL_SECONDS = 0.25

local RunController = {}
RunController.__index = RunController

export type RunController = typeof(setmetatable(
	{} :: {
		_status: RunStatus,
		_statusCallbacks: { StatusCallback },
		_roundStartCallback: RoundStartCallback?,
		_director: Director?,
		_enemiesFolder: Folder?,
		_runState: RunState?,
		_running: boolean,
	},
	RunController
))

function RunController.new(): RunController
	return setmetatable({
		_status = {
			phase = "prep" :: Phase,
			round = 1,
			totalRounds = Constants.TOTAL_ROUNDS,
			deadline = nil,
			result = nil,
		},
		_statusCallbacks = {},
		_roundStartCallback = nil,
		_director = nil,
		_enemiesFolder = nil,
		_runState = nil,
		_running = false,
	}, RunController)
end

function RunController.bindDirector(self: RunController, director: Director)
	self._director = director
end

function RunController.bindEnemiesFolder(self: RunController, folder: Folder)
	self._enemiesFolder = folder
end

-- Wires loss cancellation. When RunState fires "loss", we flip the phase
-- to "defeat" and the run loop notices on its next cancellation check.
function RunController.bindRunState(self: RunController, runState: RunState)
	self._runState = runState
	runState:onResult(function(result: Result)
		if result == "loss" then
			self:_setStatus({
				phase = "defeat",
				round = self._status.round,
				totalRounds = self._status.totalRounds,
				deadline = nil,
				result = "loss",
			})
			self._running = false
		end
	end)
end

function RunController.onStatusChanged(self: RunController, callback: StatusCallback)
	table.insert(self._statusCallbacks, callback)
	-- Hand the listener the current snapshot so a late subscriber
	-- (e.g. a player joining mid-prep) doesn't render an empty HUD
	-- until the next phase transition.
	task.spawn(callback, self._status)
end

-- Fires once per round entering its wave phase. Main uses this to
-- (re)broadcast wave state and wire any per-round side effects.
function RunController.onRoundStart(self: RunController, callback: RoundStartCallback)
	self._roundStartCallback = callback
end

function RunController.status(self: RunController): RunStatus
	return self._status
end

function RunController._setStatus(self: RunController, status: RunStatus)
	self._status = status
	for _, cb in ipairs(self._statusCallbacks) do
		task.spawn(cb, status)
	end
end

function RunController._isCancelled(self: RunController): boolean
	return not self._running or self._status.result ~= nil
end

local function waitUntilDeadline(self: RunController, deadline: number)
	while workspace:GetServerTimeNow() < deadline do
		if self:_isCancelled() then
			return
		end
		task.wait(POLL_INTERVAL_SECONDS)
	end
end

local function waitForRoundClear(self: RunController): boolean
	local director = self._director
	local folder = self._enemiesFolder
	if not director or not folder then
		warn("[RunController] No director / enemies folder bound — round will never clear")
		return false
	end
	while not self:_isCancelled() do
		if director:isFinished() and #folder:GetChildren() == 0 then
			return true
		end
		task.wait(POLL_INTERVAL_SECONDS)
	end
	return false
end

function RunController._runLoop(self: RunController)
	for roundIdx = 1, Constants.TOTAL_ROUNDS do
		if self:_isCancelled() then return end

		-- ─── Prep phase ──────────────────────────────────
		local prepDeadline = workspace:GetServerTimeNow() + Constants.PREP_PHASE_SECONDS
		self:_setStatus({
			phase = "prep",
			round = roundIdx,
			totalRounds = Constants.TOTAL_ROUNDS,
			deadline = prepDeadline,
			result = nil,
		})
		waitUntilDeadline(self, prepDeadline)
		if self:_isCancelled() then return end

		-- ─── Wave phase ──────────────────────────────────
		self:_setStatus({
			phase = "wave",
			round = roundIdx,
			totalRounds = Constants.TOTAL_ROUNDS,
			deadline = nil,
			result = nil,
		})
		if self._director then
			-- reset() is a no-op on the very first round (director is
			-- already at zero), but it's safe to call and keeps the
			-- per-round invariant uniform: every wave phase begins
			-- with a fresh schedule cursor.
			self._director:reset()
		end
		local cb = self._roundStartCallback
		if cb then
			task.spawn(cb, roundIdx)
		end
		if self._director then
			self._director:start()
		end

		local cleared = waitForRoundClear(self)
		if not cleared then
			-- Cancelled (loss or external stop). Director will be
			-- shut down by the result handler in Main.
			return
		end

		if self._director then
			self._director:stop()
		end

		-- ─── Debrief (skipped after the final round) ────
		if roundIdx < Constants.TOTAL_ROUNDS then
			local debriefDeadline = workspace:GetServerTimeNow() + Constants.DEBRIEF_SECONDS
			self:_setStatus({
				phase = "debrief",
				round = roundIdx,
				totalRounds = Constants.TOTAL_ROUNDS,
				deadline = debriefDeadline,
				result = nil,
			})
			waitUntilDeadline(self, debriefDeadline)
		end
	end

	if self:_isCancelled() then return end

	-- ─── Victory ─────────────────────────────────────
	self:_setStatus({
		phase = "victory",
		round = Constants.TOTAL_ROUNDS,
		totalRounds = Constants.TOTAL_ROUNDS,
		deadline = nil,
		result = "win",
	})
	self._running = false
	if self._runState then
		self._runState:setResult("win")
	end
end

function RunController.start(self: RunController)
	if self._running then
		return
	end
	self._running = true
	task.spawn(function()
		self:_runLoop()
	end)
end

function RunController.stop(self: RunController)
	self._running = false
end

return RunController
