class_name SectorsData extends RefCounted
##
## Sector geometry for v0. The original Sectors.lua is in 3D Roblox studs;
## here we translate to a 2D viewport. The width/depth ratio is preserved.
##
## Layout in viewport pixels (1920×1080, with the bottom 320px reserved for
## the hand band — Val strip + ability rail + cards): the playable sector
## is 1920×616 above the hand.
##   - spawn pad on the left
##   - core to the right of the spawn pad
##   - enemy entry beyond the core's far edge (right edge of the screen)

const SECTOR_LEFT := 0
const SECTOR_RIGHT := 1920
const SECTOR_TOP := 144
const SECTOR_BOTTOM := 760
const HAND_TOP := SECTOR_BOTTOM

# Pixel anchors inside the sector. Lay everything out around the vertical
# midline (y = 452) so the hero, spawn pad and core read on a common axis.
const SPAWN_PAD_CENTER := Vector2(240, 452)
const SPAWN_PAD_SIZE := Vector2(140, 140)
const CORE_CENTER := Vector2(1620, 452)
const CORE_SIZE := Vector2(96, 96)
const CORE_HEALTH := 1000.0

# Enemies spawn off-screen and walk left toward the core.
const ENEMY_ENTRY_X := 1900
const ENEMY_TARGET := CORE_CENTER

const Buffalo := {
	"id": "Buffalo",
	"floor_color_key": "Buffalo",
	"core_color_key": "Buffalo",
}

const Goose := {
	"id": "Goose",
	"floor_color_key": "Goose",
	"core_color_key": "Goose",
}

const Fox := {
	"id": "Fox",
	"floor_color_key": "Fox",
	"core_color_key": "Fox",
}

const BY_HERO := {
	"Buffalo": Buffalo,
	"Goose": Goose,
	"Fox": Fox,
}

static func is_inside_sector(point: Vector2) -> bool:
	return (point.x >= SECTOR_LEFT and point.x <= SECTOR_RIGHT
		and point.y >= SECTOR_TOP and point.y <= SECTOR_BOTTOM)
