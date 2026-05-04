class_name SectorsData extends RefCounted
##
## Sector geometry for v0. The original Sectors.lua is in 3D Roblox studs;
## here we translate to a 2D viewport. The width/depth ratio is preserved.
##
## Layout in viewport pixels (1280×720, with the bottom 240px reserved for
## the card hand): the playable sector is roughly 1280×440 above the hand.
##   - spawn pad on the left
##   - core to the right of the spawn pad
##   - enemy entry beyond the core's far edge (right edge of the screen)

const SECTOR_LEFT := 0
const SECTOR_RIGHT := 1280
const SECTOR_TOP := 80
const SECTOR_BOTTOM := 480
const HAND_TOP := SECTOR_BOTTOM

# Pixel anchors inside the sector.
const SPAWN_PAD_CENTER := Vector2(160, 280)
const SPAWN_PAD_SIZE := Vector2(120, 120)
const CORE_CENTER := Vector2(960, 280)
const CORE_SIZE := Vector2(80, 80)
const CORE_HEALTH := 1000.0

# Enemies spawn off-screen and walk left toward the core.
const ENEMY_ENTRY_X := 1320
const ENEMY_TARGET := CORE_CENTER

const Buffalo := {
	"id": "Buffalo",
	"floor_color_key": "Buffalo",
	"core_color_key": "Buffalo",
}

static func is_inside_sector(point: Vector2) -> bool:
	return (point.x >= SECTOR_LEFT and point.x <= SECTOR_RIGHT
		and point.y >= SECTOR_TOP and point.y <= SECTOR_BOTTOM)
