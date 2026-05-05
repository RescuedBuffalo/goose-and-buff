class_name EnemiesData extends RefCounted
##
## Enemy archetypes. Pixel scale: GruntMelee Waves.lua "attack range 3 studs"
## maps to 32 px → 1 stud ≈ 10.67 px. Ranges below are converted accordingly.
##
## keep_distance  — ranged archetypes back away when target closes inside
##                  preferred_range instead of advancing to melee.

const GruntMelee := {
	"id": "GruntMelee",
	"name": "Grunt",
	"health": 30.0,
	"damage": 6.0,
	"attackRange": 32.0,   # 3 studs
	"attackInterval": 1.0,
	"moveSpeed": 70.0,
	"size": Vector2(28, 28),
	"color_rgba": Color8(180, 60, 60),
	"keep_distance": false,
	"preferred_range": 0.0,
}

# Fragile skirmisher — attacks at distance, retreats when units close in.
const GruntRanged := {
	"id": "GruntRanged",
	"name": "Ranged Grunt",
	"health": 22.0,
	"damage": 8.0,
	"attackRange": 235.0,  # 22 studs
	"attackInterval": 1.4,
	"moveSpeed": 65.0,
	"size": Vector2(20, 20),
	"color_rgba": Color8(60, 140, 210),
	"keep_distance": true,
	"preferred_range": 150.0,
}

# Slow brawler — high HP, targets anchors and the core.
const Bruiser := {
	"id": "Bruiser",
	"name": "Bruiser",
	"health": 120.0,
	"damage": 18.0,
	"attackRange": 43.0,   # 4 studs
	"attackInterval": 1.5,
	"moveSpeed": 40.0,
	"size": Vector2(40, 40),
	"color_rgba": Color8(140, 50, 180),
	"keep_distance": false,
	"preferred_range": 0.0,
}

const ALL := {
	"GruntMelee": GruntMelee,
	"GruntRanged": GruntRanged,
	"Bruiser": Bruiser,
}
