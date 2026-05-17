class_name BuffaloRigParts
extends Resource
##
## Buffalo rigging-sheet part atlas (BUF-183 Phase 3).
##
## Each entry maps a logical part name to a Rect2i covering that part on
## buffalo_rigging_sheet.png. Loaded at runtime by buffalo.gd; AtlasTextures
## are constructed dynamically and assigned to the rig's Sprite2D slots.
##
## Components were sourced via scripts/tests/find_rig_parts.py running
## connected-component analysis on the transparent-background source PNG,
## then matched to labels visually against the rigging-sheet preview.
##
## Naming convention: the part keys here align with logical names used by
## CharacterRigController.register_part(); per-character scenes pick which
## parts to assign (Buffalo uses a 2-segment arm — upper_arm + hand — and a
## 2-segment leg — thigh + calf-with-hoof — so the bipedal template's
## forearm/foot slots are intentionally unassigned).

const SHEET_PATH := "res://design/assets/characters/buffalo_rigging_sheet.png"

# ── Heads ─────────────────────────────────────────────────────────────────
const HEAD_NEUTRAL := Rect2i(349, 55, 166, 148)
const HEAD_HAPPY := Rect2i(532, 55, 165, 150)
const HEAD_ANGRY := Rect2i(712, 55, 159, 150)
const HEAD_WINK := Rect2i(887, 55, 166, 148)
const HEAD_CLOSED := Rect2i(1068, 55, 162, 148)

# ── Eye states (open/half/closed pairs) ───────────────────────────────────
const EYE_OPEN_L := Rect2i(375, 261, 39, 32)
const EYE_OPEN_R := Rect2i(439, 261, 39, 32)
const EYE_HALF_L := Rect2i(542, 260, 41, 31)
const EYE_HALF_R := Rect2i(609, 260, 42, 31)
const EYE_CLOSED_L := Rect2i(679, 262, 55, 25)
const EYE_CLOSED_R := Rect2i(758, 261, 50, 27)

# ── Mouth shapes (Preston-Blair phoneme set) ──────────────────────────────
const MOUTH_A := Rect2i(375, 310, 38, 34)
const MOUTH_O := Rect2i(439, 310, 39, 34)
const MOUTH_E := Rect2i(542, 311, 41, 32)
const MOUTH_L := Rect2i(686, 313, 45, 30)
const MOUTH_S := Rect2i(758, 313, 51, 30)
const MOUTH_FV := Rect2i(832, 315, 49, 24)
const MOUTH_REST := Rect2i(1188, 345, 30, 27)

# ── Body / clothing ───────────────────────────────────────────────────────
const TORSO := Rect2i(399, 387, 137, 169)        # chest fur silhouette under the jacket
const JACKET := Rect2i(582, 392, 210, 160)        # orange parka — the visible body
const HOOD_TRIM := Rect2i(815, 415, 162, 105)     # cream collar fluff layered over jacket top
const HORN_L := Rect2i(1020, 428, 74, 81)
const HORN_R := Rect2i(1157, 428, 73, 80)
const CHEST_FUR := Rect2i(1090, 524, 128, 100)    # fluffy chest poof, layered above jacket center
const TAIL := Rect2i(1036, 615, 72, 97)           # tightened to exclude the "CHEST FUR" label
                                                   # that bled into the connected component during
                                                   # auto-detection. Tail content is the left ~72px;
                                                   # everything past x=1108 is the text label.

# ── Arms (Buffalo's are 2-segment: sleeve + hand) ─────────────────────────
const UPPER_ARM_L := Rect2i(64, 450, 87, 128)     # sleeve covering upper + forearm
const UPPER_ARM_R := Rect2i(210, 450, 84, 128)
const FOREARM_L := Rect2i(80, 579, 112, 89)       # short cuff visual; mostly the wrist + glove
const FOREARM_R := Rect2i(218, 575, 106, 95)

# ── Hand pose variants ────────────────────────────────────────────────────
const HAND_POSE_A := Rect2i(59, 717, 55, 86)
const HAND_POSE_B := Rect2i(139, 725, 49, 77)
const HAND_POSE_C := Rect2i(217, 728, 50, 74)
const HAND_POSE_D := Rect2i(294, 710, 48, 93)

# ── Legs (segmented version: thigh + calf-with-hoof) ──────────────────────
const THIGH := Rect2i(656, 587, 106, 142)         # upper leg piece (used for both sides + flip)
const CALF_HOOF := Rect2i(806, 573, 87, 147)      # lower leg + attached hoof

# ── Hoof / foot variants ──────────────────────────────────────────────────
const HOOF_A := Rect2i(673, 717, 74, 87)
const HOOF_B := Rect2i(795, 711, 65, 92)
const HOOF_C := Rect2i(924, 713, 78, 92)
