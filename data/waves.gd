class_name WavesData extends RefCounted
##
## Wave compositions per night. The survival rebuild reframes "round" as
## "night" — Night 1 / 2 / 3 escalate frost-wolf pressure on the lodge.
##
## Owl + bear archetypes are designed and locked but not in MVP scope;
## once their sprites land they fold in here. Night 3 is intentionally
## tunable — flagged as a balance question in PROTOTYPE-NOTES.

const ROUNDS := [
	{
		"index": 1,
		"name": "First night",
		"enemies": [
			{"type": "FrostWolf", "count": 6, "spawn_interval": 2.5},
		],
	},
	{
		"index": 2,
		"name": "Second night",
		"enemies": [
			{"type": "FrostWolf", "count": 9, "spawn_interval": 2.0},
		],
	},
	{
		"index": 3,
		"name": "Third night",
		"enemies": [
			{"type": "FrostWolf", "count": 12, "spawn_interval": 1.6},
		],
	},
]

const TOTAL_ROUNDS := 3

static func for_round(round_index: int) -> Dictionary:
	# Rounds (nights) are 1-indexed in design language.
	return ROUNDS[clamp(round_index - 1, 0, ROUNDS.size() - 1)]
