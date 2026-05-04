class_name WavesData extends RefCounted
##
## Wave compositions per round. v0 prototype is single-player Buffalo only
## with a fixed 3-round loop. Each round is one wave of 8 GruntMelee.

const ROUNDS := [
	{
		"index": 1,
		"name": "Probe",
		"enemies": [{"type": "GruntMelee", "count": 8, "spawn_interval": 0.7}],
	},
	{
		"index": 2,
		"name": "Pressure",
		"enemies": [{"type": "GruntMelee", "count": 8, "spawn_interval": 0.55}],
	},
	{
		"index": 3,
		"name": "Heavy charge",
		"enemies": [{"type": "GruntMelee", "count": 8, "spawn_interval": 0.4}],
	},
]

const TOTAL_ROUNDS := 3

static func for_round(round_index: int) -> Dictionary:
	# Rounds are 1-indexed in design language.
	return ROUNDS[clamp(round_index - 1, 0, ROUNDS.size() - 1)]
