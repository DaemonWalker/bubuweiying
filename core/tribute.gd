class_name Tribute
extends RefCounted
## 进贡（喝血）：数量与方向计算（规则 §5）、贡牌与还贡的合法性。

const SCORE_LOW := 80
const SCORE_FLIP_MIN := 120
const SCORE_FLIP_MAX := 150
const STEP := 10
const BIG_JOKER_BONUS := 2
const SMALL_JOKER_BONUS := 1


## 基础贡牌张数（规则 §5；s 为上局抓分方总分）：
## s<80 → 1+⌈(80-s)/10⌉；80≤s<120 → 1；120≤s≤150 → 1（方向反转）；s>150 → 1+⌈(s-150)/10⌉。
## 规则未定义 116~119，按 80~115 区间处理为 1 张。
static func base_count(s: int) -> int:
	if s < SCORE_LOW:
		return 1 + ceili(float(SCORE_LOW - s) / STEP)
	if s <= SCORE_FLIP_MAX:
		return 1
	return 1 + ceili(float(s - SCORE_FLIP_MAX) / STEP)


## 是否攻守易位（规则 §5：抓分方得分 120~150 时，由原庄家方向新庄家方进贡）。
static func is_reversed(s: int) -> bool:
	return s >= SCORE_FLIP_MIN and s <= SCORE_FLIP_MAX


## 底牌王加成张数（规则 §5）：每张大王 +2，每张小王 +1。
static func joker_bonus(big_jokers: int, small_jokers: int) -> int:
	return big_jokers * BIG_JOKER_BONUS + small_jokers * SMALL_JOKER_BONUS


## 总贡牌张数。bonus_active 为王奖励是否生效（见规则 §8；干锅局与分支 5 传 false）。
static func total_count(s: int, big_jokers: int, small_jokers: int, bonus_active: bool) -> int:
	var total := base_count(s)
	if bonus_active:
		total += joker_bonus(big_jokers, small_jokers)
	return total


## 贡牌合法性（规则 §5）：每张必须是贡牌者手中最大的牌（分牌除外）。
## 即 offered 全部为非分牌、在手中，且牌力不低于手中第 offered.size() 大的非分牌。
static func can_tribute(hand: Array[Card], offered: Array[Card], level: int, trump_suit: int) -> bool:
	if offered.is_empty():
		return false
	var candidates: Array[Card] = []
	for card in hand:
		if card.score_value() == 0:
			candidates.append(card)
	if offered.size() > candidates.size():
		return false
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump_suit) > Play.power(b, level, trump_suit))
	var threshold := Play.power(candidates[offered.size() - 1], level, trump_suit)
	for card in offered:
		if card.score_value() != 0:
			return false
		if not Card.contains_identical(hand, card):
			return false
		if Play.power(card, level, trump_suit) < threshold:
			return false
	return true


## 还贡合法性（规则 §5）：每张都是非分牌副牌，由庄家自由选牌。
static func can_return(cards: Array[Card], level: int, trump_suit: int) -> bool:
	if cards.is_empty():
		return false
	for card in cards:
		if card.score_value() != 0 or Play.is_trump(card, level, trump_suit):
			return false
	return true
