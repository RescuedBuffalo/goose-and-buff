--!strict
-- Shared constants. Pure data, no Roblox APIs.

local Constants = {}

-- Hero assignment order. First three players get these in sequence.
Constants.HEROES = { "Goose", "Buffalo", "Fox" }

Constants.MAX_PLAYERS = 3

-- BUF-92: round flow timings. The run is TOTAL_ROUNDS iterations of
-- (prep -> wave -> debrief). After the last round's wave clears, the
-- run is a victory. After any core dies, it's a defeat.
Constants.PREP_PHASE_SECONDS = 30
Constants.DEBRIEF_SECONDS = 10
Constants.TOTAL_ROUNDS = 3

-- Names of RemoteEvent/RemoteFunction Instances under ReplicatedStorage.
-- Server creates them; client :WaitForChild()s by these names.
Constants.REMOTES = {
	StateUpdate = "StateUpdate",
	-- BUF-92: phase + round + result, used by the run HUD.
	RunUpdate = "RunUpdate",
	-- BUF-92: client -> server when the player clicks Restart on the
	-- end screen. v0.1 just respawns; the lodge / true restart comes
	-- in v0.2.
	RestartRequest = "RestartRequest",
}

return Constants
