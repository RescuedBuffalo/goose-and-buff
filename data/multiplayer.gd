class_name MultiplayerData extends RefCounted
##
## Plain-data config for the M4 multiplayer foundation. Network port,
## slot count, host-code shape, position-sync cadence, reconnect window.
## Mirrors data/sectors.gd and data/run_economy.gd in style — constants
## only, no logic. Adapters and pure-logic modules read these.

const DEFAULT_PORT := 55432
const SLOT_COUNT := 3
const HOST_CODE_LENGTH := 6
const HOST_CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

# Position sync rate. Ten times per second is plenty for tile-grain
# movement at 12-22 studs/sec; the local hero animates smoothly off
# its own input prediction, remote heroes get linear-interpolated
# between received samples. A higher rate would chew bandwidth without
# making the picture meaningfully smoother for this audience.
const POSITION_SYNC_HZ := 10.0
const POSITION_SYNC_INTERVAL := 1.0 / POSITION_SYNC_HZ

# Reconnect window. If a peer drops mid-run we keep their hero alive
# under AI placeholder for this many seconds, then mark them fallen-by-
# disconnect so the run can keep going. Beyond this they're "gone quiet"
# permanently for the run.
const RECONNECT_WINDOW_SECONDS := 10.0

# Help-ability and revive timings (BUF-152 / BUF-154). Cooldowns picked
# at the conservative end of the brief's 20-30s window so a wave with
# multiple help-cast moments feels punchy without being spammy.
const HELP_ABILITY_COOLDOWN := 25.0
const REVIVE_HOLD_SECONDS := 3.0
const REVIVE_RANGE_TILES := 1
const DOWNED_TIMER_SECONDS := 30.0
const FALLEN_RESPAWN_HP_RATIO := 0.25

# Front rotation (BUF-153). Each hero has a default-associated front so
# the first-hit-hero calculation has a starting bias even when all three
# heroes cluster together. Heroes can move freely; this only seeds the
# spawn-direction picker so PROBE doesn't always pick the same target.
const HERO_FRONT_DEFAULT := {
	"Buffalo": "south",
	"Goose": "north",
	"Fox": "east",
}

const FRONT_ROTATION := ["north", "east", "south"]

# Connection state ids (BUF-155). Seasonal-frame copy is rendered by the
# HUD adapter from these ids — keep the copy in one place so a designer
# can tune voice without grepping through scripts.
const STATE_CONNECTING := "connecting"
const STATE_CONNECTED := "connected"
const STATE_RECONNECTING := "reconnecting"
const STATE_RECONNECTED := "reconnected"
const STATE_DROPPED := "dropped"
const STATE_HOST_DROPPED := "host_dropped"

static func connection_copy(state_id: String, hero_id: String) -> String:
	# Voice rule: totem names only, never personal usernames. Sentence
	# case. The "lantern" metaphor connects the connection layer to the
	# survival fiction so it doesn't read as a PC-techy "connecting…".
	match state_id:
		STATE_CONNECTING: return "%s is finding the lantern." % hero_id
		STATE_CONNECTED: return "%s has joined the watch." % hero_id
		STATE_RECONNECTING: return "%s is reconnecting…" % hero_id
		STATE_RECONNECTED: return "%s is back." % hero_id
		STATE_DROPPED: return "%s has gone quiet." % hero_id
		STATE_HOST_DROPPED: return "The lantern went out. Light it again."
		_: return ""
