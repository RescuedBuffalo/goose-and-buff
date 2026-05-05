class_name LodgeArtifactsData extends RefCounted
##
## Artifact pool for the lodge accumulation system (BUF-130).
##
## Every completed run — victory or defeat — leaves one of these behind.
## Flavor text is the whole point: short, image-first, never explanatory.
## Nobody alive in the lodge can fully account for any of these objects;
## the room remembers more than the heroes do.
##
## Schema per entry:
##   id           : stable string id, used as the save key
##   name         : short display name (sentence case)
##   flavor       : 1–2 sentence still-life evocation, never an explanation
##   category     : "worn" | "half_event" | "mark" | "trace"
##   spot         : where it lives in the lodge (door, hook, table, chair,
##                  shelf, beam, stove, bench, floor, windowsill)
##   illustration : asset ref path, "" for now (M3-polish wave generates these)
##
## v1 has zero gameplay effect — these are purely flavor / memorial. Future
## work may tie unlocks or art swaps to specific artifacts; that lives
## elsewhere. This module only owns the pool and a deterministic draw.

const SPOT_DOOR := "door"
const SPOT_HOOK := "hook"
const SPOT_TABLE := "table"
const SPOT_CHAIR := "chair"
const SPOT_SHELF := "shelf"
const SPOT_BEAM := "beam"
const SPOT_STOVE := "stove"
const SPOT_BENCH := "bench"
const SPOT_FLOOR := "floor"
const SPOT_WINDOWSILL := "windowsill"

# Reading order in the lodge — used by the UI to group artifacts by where
# in the room they sit. Lay out roughly entrance → hearth → fixtures.
const SPOT_ORDER := [
	SPOT_DOOR,
	SPOT_HOOK,
	SPOT_CHAIR,
	SPOT_TABLE,
	SPOT_BENCH,
	SPOT_STOVE,
	SPOT_SHELF,
	SPOT_WINDOWSILL,
	SPOT_BEAM,
	SPOT_FLOOR,
]

const SPOT_LABEL := {
	SPOT_DOOR: "By the door",
	SPOT_HOOK: "On the hooks",
	SPOT_CHAIR: "On the chairs",
	SPOT_TABLE: "On the table",
	SPOT_BENCH: "On the bench",
	SPOT_STOVE: "Around the stove",
	SPOT_SHELF: "On the shelves",
	SPOT_WINDOWSILL: "On the windowsill",
	SPOT_BEAM: "Across the beams",
	SPOT_FLOOR: "On the floor",
}

const ALL := {
	# ── Worn objects ─────────────────────────────────────────────────────
	"cream_scarf": {
		"id": "cream_scarf",
		"name": "A cream scarf",
		"flavor": "Coiled on the chair like it had been worn home. The Goose this run isn't wearing one.",
		"category": "worn",
		"spot": SPOT_CHAIR,
		"illustration": "",
	},
	"unmatched_mittens": {
		"id": "unmatched_mittens",
		"name": "A pair of mittens",
		"flavor": "Knit in a stitch nobody here remembers learning.",
		"category": "worn",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"green_coat": {
		"id": "green_coat",
		"name": "A heavy green coat",
		"flavor": "Too small for Buffalo, too long for Fox. The hem is wet.",
		"category": "worn",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"red_wool_cap": {
		"id": "red_wool_cap",
		"name": "A red wool cap",
		"flavor": "Fox swears it isn't theirs.",
		"category": "worn",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"wide_brim_hat": {
		"id": "wide_brim_hat",
		"name": "A wide-brimmed hat",
		"flavor": "Buffalo has tried it on. Nobody else has dared.",
		"category": "worn",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"dry_boots": {
		"id": "dry_boots",
		"name": "A pair of boots",
		"flavor": "Set neat by the door, dry. None of us came in dry tonight.",
		"category": "worn",
		"spot": SPOT_DOOR,
		"illustration": "",
	},
	"damp_socks": {
		"id": "damp_socks",
		"name": "Wool socks on the line",
		"flavor": "Strung from a beam, still damp. We haven't done a wash in weeks.",
		"category": "worn",
		"spot": SPOT_BEAM,
		"illustration": "",
	},
	"patchwork_blanket": {
		"id": "patchwork_blanket",
		"name": "A patchwork blanket",
		"flavor": "Folded over the chair. Some of the patches match a coat we burned three winters back.",
		"category": "worn",
		"spot": SPOT_CHAIR,
		"illustration": "",
	},

	# ── Half-events ──────────────────────────────────────────────────────
	"warm_mug": {
		"id": "warm_mug",
		"name": "A half-finished mug",
		"flavor": "Set down on the table. The tea is still warm.",
		"category": "half_event",
		"spot": SPOT_TABLE,
		"illustration": "",
	},
	"cooling_kettle": {
		"id": "cooling_kettle",
		"name": "A kettle on the stove",
		"flavor": "Cooling. Nobody put it there.",
		"category": "half_event",
		"spot": SPOT_STOVE,
		"illustration": "",
	},
	"new_doorbell": {
		"id": "new_doorbell",
		"name": "A small brass bell",
		"flavor": "Hung over the door. It wasn't there yesterday.",
		"category": "half_event",
		"spot": SPOT_DOOR,
		"illustration": "",
	},
	"smoking_lantern": {
		"id": "smoking_lantern",
		"name": "A lantern, just out",
		"flavor": "Sat on the bench. The wick is still smoking.",
		"category": "half_event",
		"spot": SPOT_BENCH,
		"illustration": "",
	},
	"warm_needles": {
		"id": "warm_needles",
		"name": "An unfinished knit",
		"flavor": "A basket of yarn on the chair. The needles are warm.",
		"category": "half_event",
		"spot": SPOT_CHAIR,
		"illustration": "",
	},
	"weighted_letter": {
		"id": "weighted_letter",
		"name": "An unfinished letter",
		"flavor": "Half-written, no addressee, weighed down by a stone.",
		"category": "half_event",
		"spot": SPOT_TABLE,
		"illustration": "",
	},
	"used_candle": {
		"id": "used_candle",
		"name": "A candle stub",
		"flavor": "Burned down to almost nothing on the windowsill. We didn't light it.",
		"category": "half_event",
		"spot": SPOT_WINDOWSILL,
		"illustration": "",
	},
	"scraped_pipe": {
		"id": "scraped_pipe",
		"name": "A pipe, gone cold",
		"flavor": "Set on the bench. The bowl was scraped recently.",
		"category": "half_event",
		"spot": SPOT_BENCH,
		"illustration": "",
	},

	# ── Marks of presence ────────────────────────────────────────────────
	"carved_name": {
		"id": "carved_name",
		"name": "A name in the table",
		"flavor": "Carved into the edge. The letters don't match any hand we know.",
		"category": "mark",
		"spot": SPOT_TABLE,
		"illustration": "",
	},
	"scratched_song": {
		"id": "scratched_song",
		"name": "A song in a beam",
		"flavor": "Scratched fine. The notes don't sit on any scale we sing.",
		"category": "mark",
		"spot": SPOT_BEAM,
		"illustration": "",
	},
	"dust_footprints": {
		"id": "dust_footprints",
		"name": "Footprints in dust",
		"flavor": "Smaller than the hero who came home.",
		"category": "mark",
		"spot": SPOT_FLOOR,
		"illustration": "",
	},
	"door_tally": {
		"id": "door_tally",
		"name": "A tally on the doorpost",
		"flavor": "Eleven marks. None of us have been counting.",
		"category": "mark",
		"spot": SPOT_DOOR,
		"illustration": "",
	},

	# ── Hero-adjacent traces ─────────────────────────────────────────────
	"grey_feather": {
		"id": "grey_feather",
		"name": "A grey feather",
		"flavor": "Long. Too long for any goose we know.",
		"category": "trace",
		"spot": SPOT_TABLE,
		"illustration": "",
	},
	"river_stone": {
		"id": "river_stone",
		"name": "A river stone",
		"flavor": "Set on the table. Nobody walked to the river today.",
		"category": "trace",
		"spot": SPOT_TABLE,
		"illustration": "",
	},
	"pressed_flower": {
		"id": "pressed_flower",
		"name": "A pressed flower",
		"flavor": "Tucked in a book none of us own.",
		"category": "trace",
		"spot": SPOT_SHELF,
		"illustration": "",
	},
	"iron_key": {
		"id": "iron_key",
		"name": "An iron key",
		"flavor": "Hung by the door. We have no door it fits.",
		"category": "trace",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"stuck_compass": {
		"id": "stuck_compass",
		"name": "A small compass",
		"flavor": "Needle stuck. The lodge has only one direction.",
		"category": "trace",
		"spot": SPOT_SHELF,
		"illustration": "",
	},
	"smooth_token": {
		"id": "smooth_token",
		"name": "A wooden token",
		"flavor": "Hand-shaped, worn smooth by a thumb that wasn't yours.",
		"category": "trace",
		"spot": SPOT_SHELF,
		"illustration": "",
	},
	"unmarked_tin": {
		"id": "unmarked_tin",
		"name": "An unmarked tea tin",
		"flavor": "The label is rubbed off. The smell is not one we keep.",
		"category": "trace",
		"spot": SPOT_SHELF,
		"illustration": "",
	},
	"small_hatchet": {
		"id": "small_hatchet",
		"name": "A small hatchet",
		"flavor": "Too light for chopping. Whatever it cut was not wood.",
		"category": "trace",
		"spot": SPOT_HOOK,
		"illustration": "",
	},
	"plain_band": {
		"id": "plain_band",
		"name": "A plain band ring",
		"flavor": "Set on the windowsill. None of us are married.",
		"category": "trace",
		"spot": SPOT_WINDOWSILL,
		"illustration": "",
	},
	"bone_button": {
		"id": "bone_button",
		"name": "A bone button",
		"flavor": "Carved with a figure none of us recognize.",
		"category": "trace",
		"spot": SPOT_SHELF,
		"illustration": "",
	},
	"eaves_chime": {
		"id": "eaves_chime",
		"name": "A small chime",
		"flavor": "Tied to the eaves. It rings before the wind, not after.",
		"category": "trace",
		"spot": SPOT_BEAM,
		"illustration": "",
	},
}

# Stable ordering so artifact draws are reproducible from a seeded RNG.
# Dictionary key order in GDScript is insertion order, so this list mirrors
# ALL above without depending on it being honored elsewhere.
const ORDER := [
	"cream_scarf",
	"unmatched_mittens",
	"green_coat",
	"red_wool_cap",
	"wide_brim_hat",
	"dry_boots",
	"damp_socks",
	"patchwork_blanket",
	"warm_mug",
	"cooling_kettle",
	"new_doorbell",
	"smoking_lantern",
	"warm_needles",
	"weighted_letter",
	"used_candle",
	"scraped_pipe",
	"carved_name",
	"scratched_song",
	"dust_footprints",
	"door_tally",
	"grey_feather",
	"river_stone",
	"pressed_flower",
	"iron_key",
	"stuck_compass",
	"smooth_token",
	"unmarked_tin",
	"small_hatchet",
	"plain_band",
	"bone_button",
	"eaves_chime",
]

# ── Accessors ────────────────────────────────────────────────────────────

static func get_artifact(artifact_id: String) -> Dictionary:
	return ALL.get(artifact_id, {})

static func has_artifact(artifact_id: String) -> bool:
	return ALL.has(artifact_id)

static func ids() -> Array:
	return ORDER.duplicate()

static func count() -> int:
	return ORDER.size()

# ── Draw ─────────────────────────────────────────────────────────────────
#
# The lodge "only accumulates" per the spec, so duplicates across runs are
# fine — every run leaves a mark, even if the same kind of mark was left
# before. RNG is injected so tests can seed; production callers pass a
# fresh RandomNumberGenerator.
static func draw(rng: RandomNumberGenerator) -> String:
	if ORDER.is_empty():
		return ""
	var idx := rng.randi_range(0, ORDER.size() - 1)
	return ORDER[idx]
