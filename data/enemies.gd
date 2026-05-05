class_name EnemiesData extends RefCounted
##
## Enemy archetypes. The wave-defense build leaned on Grunt / Bruiser
## variants; the survival rebuild adds FrostWolf as the canonical MVP
## raider, plus three frost-themed variants (DireWolf, FrostStalker,
## AlphaWolf) introduced in BUF-114 to back the wave archetypes. Old
## Grunt / Bruiser entries stay so the data isn't lost — they fold back
## into night composition once owl + bear sprites land.

const FrostWolf := {
	"id": "FrostWolf",
	"name": "Frost wolf",
	"health": 35.0,
	"damage": 8.0,
	"attackRange": 32.0,    # tile-adjacent
	"coreRange": 32.0,
	"attackInterval": 1.0,
	"moveSpeed": 80.0,
	"size": Vector2(32, 26),
	"color_rgba": Color8(180, 196, 220),
	"keep_distance": false,
	"preferred_range": 0.0,
}

# Rush variant — leaner, faster wolf. Used by RUSH archetype to flood
# the lodge with bodies that test the player's swing arc rather than
# their trade math.
const DireWolf := {
	"id": "DireWolf",
	"name": "Dire wolf",
	"health": 22.0,
	"damage": 6.0,
	"attackRange": 32.0,
	"coreRange": 32.0,
	"attackInterval": 0.9,
	"moveSpeed": 120.0,
	"size": Vector2(30, 24),
	"color_rgba": Color8(150, 170, 200),
	"keep_distance": false,
	"preferred_range": 0.0,
}

# Skirmish variant — keeps distance, plinks from range. Reuses the
# `keep_distance` AI plumbing the old GruntRanged pioneered. Frost-themed
# rather than the original blue rect so the world stays coherent.
const FrostStalker := {
	"id": "FrostStalker",
	"name": "Frost stalker",
	"health": 24.0,
	"damage": 7.0,
	"attackRange": 235.0,
	"coreRange": 32.0,
	"attackInterval": 1.4,
	"moveSpeed": 65.0,
	"size": Vector2(22, 22),
	"color_rgba": Color8(120, 160, 220),
	"keep_distance": true,
	"preferred_range": 150.0,
}

# Mini-boss — Bruiser variant per the BUF-114 brief. Slow, heavy-hitter
# wolf with ~2x Bruiser HP so it survives long enough to feel like a
# moment. Always shows up on Night 3 SIEGE.
const AlphaWolf := {
	"id": "AlphaWolf",
	"name": "Alpha wolf",
	"health": 220.0,
	"damage": 22.0,
	"attackRange": 43.0,
	"coreRange": 43.0,
	"attackInterval": 1.4,
	"moveSpeed": 50.0,
	"size": Vector2(48, 40),
	"color_rgba": Color8(90, 110, 150),
	"keep_distance": false,
	"preferred_range": 0.0,
}

const GruntMelee := {
	"id": "GruntMelee",
	"name": "Grunt",
	"health": 30.0,
	"damage": 6.0,
	"attackRange": 32.0,
	"coreRange": 32.0,
	"attackInterval": 1.0,
	"moveSpeed": 70.0,
	"size": Vector2(28, 28),
	"color_rgba": Color8(180, 60, 60),
	"keep_distance": false,
	"preferred_range": 0.0,
}

const GruntRanged := {
	"id": "GruntRanged",
	"name": "Ranged Grunt",
	"health": 22.0,
	"damage": 8.0,
	"attackRange": 235.0,
	"coreRange": 32.0,
	"attackInterval": 1.4,
	"moveSpeed": 65.0,
	"size": Vector2(20, 20),
	"color_rgba": Color8(60, 140, 210),
	"keep_distance": true,
	"preferred_range": 150.0,
}

const Bruiser := {
	"id": "Bruiser",
	"name": "Bruiser",
	"health": 120.0,
	"damage": 18.0,
	"attackRange": 43.0,
	"coreRange": 43.0,
	"attackInterval": 1.5,
	"moveSpeed": 40.0,
	"size": Vector2(40, 40),
	"color_rgba": Color8(140, 50, 180),
	"keep_distance": false,
	"preferred_range": 0.0,
}

const ALL := {
	"FrostWolf": FrostWolf,
	"DireWolf": DireWolf,
	"FrostStalker": FrostStalker,
	"AlphaWolf": AlphaWolf,
	"GruntMelee": GruntMelee,
	"GruntRanged": GruntRanged,
	"Bruiser": Bruiser,
}
