--!strict
-- Pure data: wave composition per targeted hero. Read by WaveDirector when a
-- scheduled wave fires. Composition is the "secret" payload BUF-91 reveals
-- only to the first-hit player; teammates see the redacted view.
--
-- Shape per entry:
--   name      : human-readable wave name shown in the reveal panel
--   enemies   : ordered list of { type, count, formation }
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
			{ type = "Scout", count = 6, formation = "Cluster" },
			{ type = "Drone", count = 2, formation = "Wedge" },
		},
	},
	Goose = {
		name = "Sky Hunters",
		enemies = {
			{ type = "Drone", count = 4, formation = "Wedge" },
			{ type = "Scout", count = 3, formation = "Cluster" },
		},
	},
	Buffalo = {
		name = "Heavy Charge",
		enemies = {
			{ type = "Brute", count = 2, formation = "Line" },
			{ type = "Scout", count = 4, formation = "Cluster" },
		},
	},
} :: { [string]: WaveComposition }

return Waves
