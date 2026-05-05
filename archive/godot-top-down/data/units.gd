class_name UnitsData extends RefCounted
##
## Mirror of game1/units-data.md / Units.lua. Three archetypes × three
## factions = nine units. v0 prototype only uses the Buffalo set, but all
## nine are listed so we don't have to grow the table later.

const Calf := {
	"id": "Calf", "faction": "Buffalo", "archetype": "light", "theme": "plains",
	"health": 70, "damage": 6, "moveSpeed": 14,
	"attackRange": 4, "attackInterval": 0.8, "cost": 28,
	"flavor": "Wide stance from the start.",
}

const Ostrich := {
	"id": "Ostrich", "faction": "Buffalo", "archetype": "ranged", "theme": "plains",
	"health": 55, "damage": 14, "moveSpeed": 13,
	"attackRange": 14, "attackInterval": 1.3, "cost": 40,
	"knockbackStuds": 6,
	"flavor": "Kicks at mid-range. Knockback included.",
}

const Longhorn := {
	"id": "Longhorn", "faction": "Buffalo", "archetype": "heavy", "theme": "plains",
	"health": 180, "damage": 14, "moveSpeed": 9,
	"attackRange": 4, "attackInterval": 1.6, "cost": 80,
	"flavor": "The wall. Don't try to go through.",
}

const Gosling := {
	"id": "Gosling", "faction": "Goose", "archetype": "light", "theme": "bird",
	"health": 55, "damage": 7, "moveSpeed": 18,
	"attackRange": 4, "attackInterval": 0.7, "cost": 22,
	"flavor": "Cheap, scrappy, in numbers.",
}

const Heron := {
	"id": "Heron", "faction": "Goose", "archetype": "ranged", "theme": "bird",
	"health": 38, "damage": 11, "moveSpeed": 15,
	"attackRange": 32, "attackInterval": 1.2, "cost": 35,
	"flavor": "Long spear-strike. Stays in the back.",
}

const Swan := {
	"id": "Swan", "faction": "Goose", "archetype": "heavy", "theme": "bird",
	"health": 130, "damage": 13, "moveSpeed": 12,
	"attackRange": 4, "attackInterval": 1.4, "cost": 70,
	"flavor": "Hisses. Charges. Surprisingly mean.",
}

const Kit := {
	"id": "Kit", "faction": "Fox", "archetype": "light", "theme": "forest",
	"health": 42, "damage": 8, "moveSpeed": 22,
	"attackRange": 3, "attackInterval": 0.6, "cost": 25,
	"flavor": "Faster than it should be. Bites.",
}

const Lynx := {
	"id": "Lynx", "faction": "Fox", "archetype": "ranged", "theme": "forest",
	"health": 35, "damage": 16, "moveSpeed": 18,
	"attackRange": 22, "attackInterval": 1.5, "cost": 45,
	"ambushDamageBonus": 1.5,
	"flavor": "Stalks. Strikes once, hard.",
}

const Badger := {
	"id": "Badger", "faction": "Fox", "archetype": "heavy", "theme": "forest",
	"health": 110, "damage": 16, "moveSpeed": 11,
	"attackRange": 4, "attackInterval": 1.5, "cost": 70,
	"evasionChance": 0.10,
	"flavor": "Stocky and stubborn. Hard to pin down.",
}

const ALL := {
	"Calf": Calf, "Ostrich": Ostrich, "Longhorn": Longhorn,
	"Gosling": Gosling, "Heron": Heron, "Swan": Swan,
	"Kit": Kit, "Lynx": Lynx, "Badger": Badger,
}
