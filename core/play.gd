class_name Play
extends RefCounted
## 牌型识别与两手牌的大小比较（规则 §7）。

## 牌型：单张 / 棒子（两张完全相同）/ 滚子（三张完全相同），枚举值与张数对齐。
enum Type { INVALID, SINGLE, STICK, ROLLER }

const POWER_BIG_JOKER := 1000
const POWER_SMALL_JOKER := 900
const POWER_TRUMP_LEVEL := 800
const POWER_SIDE_LEVEL := 700
const POWER_TRUMP_TWO := 600
const POWER_SIDE_TWO := 500
const POWER_TRUMP_BASE := 100


## 识别牌型（规则 §7.1）：1 张单张 / 2 张完全相同为棒子 / 3 张完全相同为滚子，其余非法。
static func identify(cards: Array[Card]) -> int:
	if cards.is_empty() or cards.size() > 3:
		return Type.INVALID
	for i in range(1, cards.size()):
		if not cards[0].same_card(cards[i]):
			return Type.INVALID
	return cards.size()


## 是否主牌：王 / 级牌（任意花色）/ 2（任意花色）/ 主花色牌（规则 §3）。
static func is_trump(card: Card, level: int, trump_suit: int) -> bool:
	return card.is_joker() or card.rank == level or card.rank == 2 or card.suit == trump_suit


## 牌力数值（规则 §3 牌力序）。只在同一比较语境内有意义：
## 大王 > 小王 > 主级牌 > 副级牌（三花色同级）> 主 2 > 副 2 > 主花色普通牌 > 副牌。
static func power(card: Card, level: int, trump_suit: int) -> int:
	if card.rank == Card.RANK_BIG_JOKER:
		return POWER_BIG_JOKER
	if card.rank == Card.RANK_SMALL_JOKER:
		return POWER_SMALL_JOKER
	if card.rank == level:
		return POWER_TRUMP_LEVEL if card.suit == trump_suit else POWER_SIDE_LEVEL
	if card.rank == 2:
		return POWER_TRUMP_TWO if card.suit == trump_suit else POWER_SIDE_TWO
	if card.suit == trump_suit:
		return POWER_TRUMP_BASE + card.rank
	return card.rank


## follow 是否压过 lead（规则 §7.3）。要求张数相同、双方牌型合法且同牌型；
## 主杀副须同牌型；垫牌（非同花色非主）恒判小；不同花色副牌互不比大小。
static func beats(lead: Array[Card], follow: Array[Card], level: int, trump_suit: int) -> bool:
	if lead.size() != follow.size():
		return false
	var lead_type := identify(lead)
	if lead_type == Type.INVALID or identify(follow) != lead_type:
		return false
	var lead_trump := is_trump(lead[0], level, trump_suit)
	var follow_trump := is_trump(follow[0], level, trump_suit)
	if lead_trump:
		if not follow_trump:
			return false
	elif not follow_trump and follow[0].suit != lead[0].suit:
		return false
	return power(follow[0], level, trump_suit) > power(lead[0], level, trump_suit)
