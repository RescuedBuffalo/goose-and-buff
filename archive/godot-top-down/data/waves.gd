class_name WavesData extends RefCounted
##
## Wave compositions per round. 3-round fixed loop; each round escalates
## the archetype mix per BUF-108.
##   Wave 1 — pure GruntMelee
##   Wave 2 — GruntMelee + GruntRanged
##   Wave 3 — all three archetypes, including a pair of Bruisers

const ROUNDS := [
	{
		"index": 1,
		"name": "Probe",
		"enemies": [
			{"type": "GruntMelee", "count": 8, "spawn_interval": 0.7},
		],
	},
	{
		"index": 2,
		"name": "Pressure",
		"enemies": [
			{"type": "GruntMelee",  "count": 6, "spawn_interval": 0.55},
			{"type": "GruntRanged", "count": 4, "spawn_interval": 0.65},
		],
	},
	{
		"index": 3,
		"name": "Heavy Charge",
		"enemies": [
			{"type": "GruntMelee",  "count": 5, "spawn_interval": 0.45},
			{"type": "GruntRanged", "count": 3, "spawn_interval": 0.6},
			{"type": "Bruiser",     "count": 2, "spawn_interval": 1.5},
		],
	},
]

const TOTAL_ROUNDS := 3

static func for_round(round_index: int) -> Dictionary:
	# Rounds are 1-indexed in design language.
	return ROUNDS[clamp(round_index - 1, 0, ROUNDS.size() - 1)]
