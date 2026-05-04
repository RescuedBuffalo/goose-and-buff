class_name HeroesData extends RefCounted
##
## Mirror of src/shared/Data/Heroes.lua from the Roblox project.
## Keys are heroIds used everywhere else.
##
## Role + flavor strings come from the Long Watch design bundle's hero
## select wireframe (`design/wireframes/Wireframes.html`, surface 01).
## Hero select renders these directly — change the wireframe and this file
## together so they don't drift.

const Buffalo := {
	"id": "Buffalo",
	"name": "Buffalo",
	"role": "Sentinel anchor",
	"flavor": "Heavy. Patient. Whatever's coming through, comes through them.",
	"signatureAbility": "Buffalo charge",
	"baseHealth": 160,
	"moveSpeed": 12,
}

const Goose := {
	"id": "Goose",
	"name": "Goose",
	"role": "Aggression / IGL",
	"flavor": "Loud, fast, gets there first. Calls the shots when it counts.",
	"signatureAbility": "Goose pounce",
	"baseHealth": 100,
	"moveSpeed": 18,
}

const Fox := {
	"id": "Fox",
	"name": "Fox",
	"role": "Initiator / Recon",
	"flavor": "First in, first out. Sees what the others can't until it's too late.",
	"signatureAbility": "Fox flank",
	"baseHealth": 85,
	"moveSpeed": 22,
}

const ALL := {
	"Buffalo": Buffalo,
	"Goose": Goose,
	"Fox": Fox,
}

# Canonical pick order — matches design wireframe surface 01 (Goose · Buffalo
# · Fox). Predictable position is muscle memory; do not sort by availability.
const ORDER := ["Goose", "Buffalo", "Fox"]
