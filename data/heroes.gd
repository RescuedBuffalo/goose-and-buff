class_name HeroesData extends RefCounted
##
## Mirror of src/shared/Data/Heroes.lua from the Roblox project.
## Keys are heroIds used everywhere else.

const Buffalo := {
	"id": "Buffalo",
	"name": "Buffalo",
	"role": "Sentinel anchor",
	"flavor": "Heavy. Patient. Whatever's coming through, comes through them.",
	"signatureAbility": "Buffalo charge",
	"signatureAbilityId": "BuffaloCharge",
	"signatureCooldown": 6.0,
	"baseHealth": 160,
	"moveSpeed": 12,
}

const Goose := {
	"id": "Goose",
	"name": "Goose",
	"role": "Aggression / IGL",
	"flavor": "Loud, fast, gets there first. Calls the shots when it counts.",
	"signatureAbility": "Dive",
	"signatureAbilityId": "Dive",
	"signatureCooldown": 5.0,
	"baseHealth": 100,
	"moveSpeed": 18,
}

const Fox := {
	"id": "Fox",
	"name": "Fox",
	"role": "Initiator / Recon",
	"flavor": "First in, first out. Sees what the others can't until it's too late.",
	"signatureAbility": "Snatch",
	"signatureAbilityId": "Snatch",
	"signatureCooldown": 4.5,
	"baseHealth": 85,
	"moveSpeed": 22,
}

const ALL := {
	"Buffalo": Buffalo,
	"Goose": Goose,
	"Fox": Fox,
}

const ORDER := ["Goose", "Buffalo", "Fox"]
