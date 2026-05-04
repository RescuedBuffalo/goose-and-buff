--!strict
-- BUF-90: Click-to-damage combat.
-- Owns the (player -> heroId) registry that other systems use to resolve
-- the clicker's hero, and binds ClickDetectors to enemy torsos so a
-- click applies Heroes[heroId].baseDamage. Players with no assignment
-- (spectators, late joiners pre-assignment) click as no-ops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heroes = require(ReplicatedStorage.Data.Heroes)

local Combat = {}

local heroByPlayer: { [Player]: string } = {}

-- Generous so any defender can click anywhere in the arena. The arena
-- diagonal is well under 200 studs.
local CLICK_RANGE = 200

function Combat.bindPlayer(player: Player, heroId: string)
	heroByPlayer[player] = heroId
end

function Combat.unbindPlayer(player: Player)
	heroByPlayer[player] = nil
end

function Combat.heroFor(player: Player): string?
	return heroByPlayer[player]
end

function Combat.bindEnemyClicks(torso: BasePart, humanoid: Humanoid)
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = CLICK_RANGE
	detector.Parent = torso

	detector.MouseClick:Connect(function(player: Player)
		if humanoid.Health <= 0 then
			return
		end
		local heroId = heroByPlayer[player]
		if not heroId then
			return
		end
		local hero = Heroes[heroId]
		if not hero then
			return
		end
		humanoid:TakeDamage(hero.baseDamage)
	end)
end

return Combat
