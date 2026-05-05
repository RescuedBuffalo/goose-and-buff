class_name CardSystem extends RefCounted
##
## Pure deck / hand / discard. No scene-tree access. Adapters render
## the hand and translate drag-drop into `play_card_at()` calls.
##
## Lifecycle:
##   start_round()   -> shuffle discard back in if deck is empty, draw to HAND_SIZE
##   play_card_at()  -> validate cost + phase, emit card_played, move to discard
##   end_round()     -> any unplayed cards stay in hand for next round (simple v0)

const Cards := preload("res://data/cards.gd")

signal hand_changed(hand: Array)
signal card_played(card: Dictionary, position: Vector2)
signal play_rejected(card_id: String, reason: String)

var deck: Array = []
var hand: Array = []
var discard: Array = []

func reset(hero_id: String = "Buffalo") -> void:
	deck = Cards.build_starter_deck(hero_id)
	hand = []
	discard = []
	_shuffle(deck)

func start_round() -> void:
	while hand.size() < Cards.HAND_SIZE:
		if deck.is_empty():
			if discard.is_empty():
				break
			deck = discard
			discard = []
			_shuffle(deck)
		hand.append(deck.pop_back())
	hand_changed.emit(hand.duplicate())

func can_play(card_id: String, current_phase: String, balance: int) -> Dictionary:
	if not card_id in hand:
		return {"ok": false, "reason": "not_in_hand"}
	var card: Dictionary = Cards.get_card(card_id)
	if card.is_empty():
		return {"ok": false, "reason": "unknown_card"}
	if card.phase != current_phase:
		return {"ok": false, "reason": "wrong_phase"}
	if balance < int(card.cost):
		return {"ok": false, "reason": "insufficient_funds"}
	return {"ok": true, "card": card}

func play_card_at(card_id: String, position: Vector2, current_phase: String, balance: int) -> Dictionary:
	var check := can_play(card_id, current_phase, balance)
	if not check.ok:
		play_rejected.emit(card_id, check.reason)
		return check
	var card: Dictionary = check.card
	hand.erase(card_id)
	discard.append(card_id)
	hand_changed.emit(hand.duplicate())
	card_played.emit(card, position)
	return {"ok": true, "card": card}

func _shuffle(arr: Array) -> void:
	var n := arr.size()
	for i in range(n - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
