--!strict
-- BUF-90: Track win/loss for a v0.1 run.
--   Loss: any sector core HP <= 0.
--   Win:  the WaveDirector has announced all waves AND the Enemies folder
--         is empty (every enemy has either been killed or reached its
--         core and despawned).
--
-- Fires "win" or "loss" exactly once. Subsequent transitions are no-ops.

export type Result = "win" | "loss"
export type ResultCallback = (Result) -> ()

type Director = { isFinished: (Director) -> boolean }

local RunState = {}
RunState.__index = RunState

export type RunState = typeof(setmetatable(
	{} :: {
		_state: "running" | Result,
		_callbacks: { ResultCallback },
		_director: Director?,
		_enemiesFolder: Folder?,
	},
	RunState
))

function RunState.new(): RunState
	return setmetatable({
		_state = "running",
		_callbacks = {},
		_director = nil,
		_enemiesFolder = nil,
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

-- Public: re-evaluate the win condition. Called both internally on
-- Enemies.ChildRemoved AND externally (from Main's director:onStateChanged
-- hook) so a wave that spawns zero enemies — or an already-finished
-- director at bind time — can still trigger a win, since neither path
-- fires a ChildRemoved.
function RunState.checkWin(self: RunState)
	if self._state ~= "running" then
		return
	end
	local director = self._director
	local folder = self._enemiesFolder
	if not director or not folder then
		return
	end
	if not director:isFinished() then
		return
	end
	if #folder:GetChildren() > 0 then
		return
	end
	fire(self, "win")
end

function RunState.bindRun(self: RunState, director: Director, enemiesFolder: Folder)
	self._director = director
	self._enemiesFolder = enemiesFolder
	enemiesFolder.ChildRemoved:Connect(function()
		self:checkWin()
	end)
	-- Cover "already done at bind time" (e.g. an empty schedule) so we
	-- don't depend on a future ChildRemoved that will never fire.
	self:checkWin()
end

function RunState.result(self: RunState): Result?
	if self._state == "running" then
		return nil
	end
	return self._state :: Result
end

return RunState
