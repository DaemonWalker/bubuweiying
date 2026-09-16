class_name Deck
extends RefCounted
## 3 副牌共 162 张的构建、洗牌与发牌（规则 §1、§4.1）。

const DECK_COUNT := 3
const PLAYER_COUNT := 4
const HAND_SIZE := 39
const BOTTOM_SIZE := 6
const TOTAL_CARDS := 162


## 构建 162 张牌：3 副本 ×（4 花色 × 点数 2~14 + 大小王）。
static func build() -> Array[Card]:
	var cards: Array[Card] = []
	for copy in DECK_COUNT:
		for suit in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]:
			for rank in range(2, 15):
				cards.append(Card.create(suit, rank, copy))
		cards.append(Card.create(Card.Suit.NONE, Card.RANK_SMALL_JOKER, copy))
		cards.append(Card.create(Card.Suit.NONE, Card.RANK_BIG_JOKER, copy))
	return cards


## 构建并洗牌。seed 相同则结果相同，便于测试复现。
static func shuffled(seed: int) -> Array[Card]:
	var cards := build()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	return cards


## 发牌：按座位号递增循环逐张发，每人 39 张，余 6 张为底牌（规则 §1、§4.1）。
## 返回 {"hands": Array ×4（元素为 Array[Card]）, "bottom": Array[Card]}。
static func deal(cards: Array[Card]) -> Dictionary:
	var hands: Array[Array] = []
	for i in PLAYER_COUNT:
		var hand: Array[Card] = []
		hands.append(hand)
	for i in HAND_SIZE * PLAYER_COUNT:
		hands[i % PLAYER_COUNT].append(cards[i])
	var bottom: Array[Card] = []
	for i in range(HAND_SIZE * PLAYER_COUNT, cards.size()):
		bottom.append(cards[i])
	return {"hands": hands, "bottom": bottom}
