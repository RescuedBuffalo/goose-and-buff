class_name EnemiesData extends RefCounted
##
## Enemy archetypes. v0 prototype only uses GruntMelee — stats are taken
## from v0.1-SPEC.md ("Use enemy stats from the existing Waves.lua
## GruntMelee archetype: HP 30, damage 6, attack range 3").
##
## Color is pulled from the Roblox grunt entry to keep visual continuity.

const GruntMelee := {
	"id": "GruntMelee",
	"name": "Grunt",
	"health": 30.0,
	"damage": 6.0,
	"attackRange": 32.0,
	"attackInterval": 1.0,
	"moveSpeed": 70.0,
	"size": Vector2(28, 28),
	"color_rgba": Color8(180, 60, 60),
}

const ALL := { "GruntMelee": GruntMelee }
