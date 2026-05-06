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
	# BUF-154: cross-sector help ability (E-bound). Stampede plows a
	# damage line from Buffalo to a teammate's front, lands next to them
	# with a brief shield buff for both.
	"helpAbility": "Cross-sector stampede",
	"helpAbilityId": "BuffaloStampede",
	"helpAbilityFlavor": "Charge across the world. Land beside the friend who called.",
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
	# BUF-154: Cover drops a buff zone on a teammate — attack-speed up,
	# damage-resist up, for everyone standing inside it.
	"helpAbility": "Cover",
	"helpAbilityId": "GooseCover",
	"helpAbilityFlavor": "Drop a circle. Anyone inside swings faster, takes less.",
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
	# BUF-154: Steal marks the closest enemy on a teammate's front and
	# yanks it toward Fox while doubling the next strike's damage.
	"helpAbility": "Steal",
	"helpAbilityId": "FoxSteal",
	"helpAbilityFlavor": "Mark a wolf on their front. Pull it. Hit it twice as hard.",
	"baseHealth": 85,
	"moveSpeed": 22,
}

const ALL := {
	"Buffalo": Buffalo,
	"Goose": Goose,
	"Fox": Fox,
}

const ORDER := ["Goose", "Buffalo", "Fox"]
