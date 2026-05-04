class_name Economy extends RefCounted
##
## Pure coin balance + production tick. No scene-tree access.
## Mirror of the Roblox Economy module — `tick(dt)`, `spend(amount)`,
## `add(amount)` — plus a single building tier slot.

signal balance_changed(new_balance: int)
signal building_upgraded(tier: int, rate: float)

const STARTING_COIN := 60
const PRODUCTION_TIERS := [5.0, 8.0, 12.0]  # coin per second by tier (1-indexed)

var balance: int = STARTING_COIN
var production_tier: int = 0  # 0 = no node, 1+ = tier
var _accum: float = 0.0

func reset() -> void:
	balance = STARTING_COIN
	production_tier = 0
	_accum = 0.0
	balance_changed.emit(balance)

func tick(dt: float) -> void:
	if production_tier <= 0:
		return
	var idx: int = clamp(production_tier - 1, 0, PRODUCTION_TIERS.size() - 1)
	var rate: float = PRODUCTION_TIERS[idx]
	_accum += rate * dt
	if _accum >= 1.0:
		var whole := int(_accum)
		_accum -= whole
		balance += whole
		balance_changed.emit(balance)

func can_afford(amount: int) -> bool:
	return balance >= amount

func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	balance -= amount
	balance_changed.emit(balance)
	return true

func add(amount: int) -> void:
	balance += amount
	balance_changed.emit(balance)

func place_or_upgrade_node() -> int:
	# Returns the new tier (1, 2, 3...) capped at PRODUCTION_TIERS length.
	production_tier = min(production_tier + 1, PRODUCTION_TIERS.size())
	var rate: float = PRODUCTION_TIERS[production_tier - 1]
	building_upgraded.emit(production_tier, rate)
	return production_tier
