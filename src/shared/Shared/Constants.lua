--!strict
-- Shared constants. Pure data, no Roblox APIs.

local Constants = {}

-- Hero assignment order. First three players get these in sequence.
Constants.HEROES = { "Goose", "Buffalo", "Fox" }

Constants.MAX_PLAYERS = 3

-- Names of RemoteEvent/RemoteFunction Instances under ReplicatedStorage.
-- Server creates them; client :WaitForChild()s by these names.
Constants.REMOTES = {
	StateUpdate = "StateUpdate",
}

return Constants
