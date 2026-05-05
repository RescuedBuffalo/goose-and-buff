class_name EnemiesData extends RefCounted
##
## Enemy archetypes. The wave-defense build leaned on Grunt / Bruiser
## variants; the survival rebuild adds FrostWolf as the canonical MVP
## raider. Old archetypes stay so the data isn't lost — they fold back
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
	"GruntMelee": GruntMelee,
	"GruntRanged": GruntRanged,
	"Bruiser": Bruiser,
}
