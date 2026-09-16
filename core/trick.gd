class_name Trick
extends RefCounted
## 一轮出牌：跟牌合法性（规则 §7.2）、赢家判定与桌面分牌合计（规则 §7.3）。

const PLAYER_COUNT := 4

var leader_seat: int
var level: int
var trump_suit: int
var _seats: Array[int] = []
var _cards: Array = []  # 与 _seats 对齐，元素为 Array[Card]，按出牌顺序


func _init(p_leader_seat: int, p_level: int, p_trump_suit: int) -> void:
	leader_seat = p_leader_seat
	level = p_level
	trump_suit = p_trump_suit


## 跟牌是否合法（规则 §7.2）：张数与首家相同；牌必须在手中；
## 有同花色（首家为主牌则为主牌）必须跟，不足时可垫其他牌补齐。
## 注意：不限制牌型，首家出棒子/滚子时跟单张合法（活棒打法）。
static func can_follow(hand: Array[Card], lead: Array[Card], follow: Array[Card], p_level: int, p_trump_suit: int) -> bool:
	if lead.is_empty() or follow.size() != lead.size():
		return false
	for card in follow:
		if not Card.contains_identical(hand, card):
			return false
	var lead_trump := Play.is_trump(lead[0], p_level, p_trump_suit)
	var hand_group := 0
	for card in hand:
		if _in_lead_group(card, lead_trump, lead[0].suit, p_level, p_trump_suit):
			hand_group += 1
	var follow_group := 0
	for card in follow:
		if _in_lead_group(card, lead_trump, lead[0].suit, p_level, p_trump_suit):
			follow_group += 1
	return follow_group == mini(hand_group, lead.size())


## 首家为主牌时"同花色组"= 主牌；否则 = 该花色副牌（级牌与 2 是主牌，不算该花色副牌）。
static func _in_lead_group(card: Card, lead_trump: bool, lead_suit: int, p_level: int, p_trump_suit: int) -> bool:
	if lead_trump:
		return Play.is_trump(card, p_level, p_trump_suit)
	return card.suit == lead_suit and not Play.is_trump(card, p_level, p_trump_suit)


## 记录一手出牌。合法性须由调用方事先用 can_follow（首家用 Play.identify）校验。
func add_play(seat: int, cards: Array[Card]) -> void:
	_seats.append(seat)
	_cards.append(cards)


func is_complete() -> bool:
	return _seats.size() == PLAYER_COUNT


## 赢家座位：从首家起逐手比较，压过当前最大者成为新最大（规则 §7.3）。
func winner_seat() -> int:
	var best := 0
	for i in range(1, _seats.size()):
		var best_cards: Array[Card] = _cards[best]
		var this_cards: Array[Card] = _cards[i]
		if Play.beats(best_cards, this_cards, level, trump_suit):
			best = i
	return _seats[best]


## 桌面所有分牌的分值合计（赢家收走）。
func score() -> int:
	var total := 0
	for cards in _cards:
		for card in cards:
			total += card.score_value()
	return total
