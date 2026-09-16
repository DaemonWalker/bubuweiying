class_name Bottom
extends RefCounted
## 扣底、扣王与干锅判定（规则 §6）。

const BOTTOM_SIZE := 6


## 扣王合法性（规则 §6.2）：只能扣王；有大王必须先扣大王，没大王才能扣小王；张数不限。
## discarding 为本次要扣入底牌的王（须都在 hand 中）。
static func can_discard_jokers(hand: Array[Card], discarding: Array[Card]) -> bool:
	if discarding.is_empty():
		return false
	var hand_big := 0
	for card in hand:
		if card.is_big_joker():
			hand_big += 1
	var discard_big := 0
	var discard_small := 0
	for card in discarding:
		if card.is_big_joker():
			discard_big += 1
		elif card.is_small_joker():
			discard_small += 1
		else:
			return false
		if not Card.contains_identical(hand, card):
			return false
	return discard_small == 0 or hand_big == discard_big


## 其他三家扣王后从底牌捡补偿牌（规则 §6.3）：等量、最小、不能捡分牌。
## 即 picked 全部为非分牌、在底牌中，且牌力不高于底牌中第 picked.size() 小的非分牌。
static func can_pick_compensation(bottom_cards: Array[Card], picked: Array[Card], level: int, trump_suit: int) -> bool:
	if picked.is_empty():
		return false
	var candidates: Array[Card] = []
	for card in bottom_cards:
		if card.score_value() == 0:
			candidates.append(card)
	if picked.size() > candidates.size():
		return false
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump_suit) < Play.power(b, level, trump_suit))
	var threshold := Play.power(candidates[picked.size() - 1], level, trump_suit)
	for card in picked:
		if card.score_value() != 0:
			return false
		if not Card.contains_identical(bottom_cards, card):
			return false
		if Play.power(card, level, trump_suit) > threshold:
			return false
	return true


## 干锅判定（规则 §6.4）：公开底牌全是主牌或全是副牌。
static func is_dry_pot(bottom_cards: Array[Card], level: int, trump_suit: int) -> bool:
	if bottom_cards.is_empty():
		return false
	var first_trump := Play.is_trump(bottom_cards[0], level, trump_suit)
	for card in bottom_cards:
		if Play.is_trump(card, level, trump_suit) != first_trump:
			return false
	return true
