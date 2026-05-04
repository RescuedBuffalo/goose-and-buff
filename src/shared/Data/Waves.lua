--!strict
-- Pure data: wave composition per targeted hero. Single source of truth
-- for both BUF-89 (Adapters.WaveSpawner.spawn(hero, type, count, formation))
-- and BUF-91 (HUD reveal panel — name, enemy types, counts, formations).
--
-- Shape per entry:
--   name      : human-readable wave name shown in the reveal panel
--   enemies   : ordered list of { type, count, formation } where `type`
--               keys into shared/Waves/Enemies.lua and `formation` is one
--               of WaveSpawner's Formation strings ("loosePack",
--               "tightPack", "backline").
--
-- For v0.1 every hero has exactly one round-1 composition. Multi-round
-- variants belong to BUF-7 once the run lifecycle exists.

export type EnemyComposition = {
	type: string,
	count: number,
	formation: string,
}

export type WaveComposition = {
	name: string,
	enemies: { EnemyComposition },
}

local Waves = {}

Waves.byHero = {
	Fox = {
		name = "Recon Probe",
		enemies = {
			{ type = "runner", count = 6, formation = "backline" },
		},
	},
	Goose = {
		name = "Sky Hunters",
		enemies = {
			{ type = "grunt", count = 4, formation = "loosePack" },
		},
	},
	Buffalo = {
		name = "Heavy Charge",
		enemies = {
			{ type = "tank", count = 2, formation = "tightPack" },
		},
	},
} :: { [string]: WaveComposition }

return Waves
