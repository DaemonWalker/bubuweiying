class_name Card
extends RefCounted
## 一张牌：花色 + 点数 + 副本序号（区分 3 副牌中的相同牌）。

enum Suit { SPADE, HEART, CLUB, DIAMOND, NONE }

const RANK_SMALL_JOKER := 16
const RANK_BIG_JOKER := 17

## 花色（Suit）；王牌为 Suit.NONE。
var suit: int
## 点数：2~14（J=11，Q=12，K=13，A=14），王牌用 RANK_SMALL_JOKER / RANK_BIG_JOKER。
var rank: int
## 副本序号 0~2，区分 3 副牌中花色点数相同的两张牌。
var copy_index: int


static func create(p_suit: int, p_rank: int, p_copy_index: int = 0) -> Card:
	var card := Card.new()
	card.suit = p_suit
	card.rank = p_rank
	card.copy_index = p_copy_index
	return card


## 手牌中是否存在与 card 完全相同（含副本序号）的一张。
static func contains_identical(hand: Array[Card], card: Card) -> bool:
	for h in hand:
		if h.is_identical(card):
			return true
	return false


## 是否王牌（大王或小王）。
func is_joker() -> bool:
	return rank == RANK_SMALL_JOKER or rank == RANK_BIG_JOKER


func is_big_joker() -> bool:
	return rank == RANK_BIG_JOKER


func is_small_joker() -> bool:
	return rank == RANK_SMALL_JOKER


## 分牌分值：5=5 分，10/K=10 分，其余 0（规则 §1）。
func score_value() -> int:
	if rank == 5:
		return 5
	if rank == 10 or rank == 13:
		return 10
	return 0


## 花色与点数是否相同（忽略副本序号）。
func same_card(other: Card) -> bool:
	return suit == other.suit and rank == other.rank


## 是否完全同一张牌（含副本序号）。
func is_identical(other: Card) -> bool:
	return same_card(other) and copy_index == other.copy_index


func _to_string() -> String:
	if rank == RANK_BIG_JOKER:
		return "大王#%d" % copy_index
	if rank == RANK_SMALL_JOKER:
		return "小王#%d" % copy_index
	var suits := ["♠", "♥", "♣", "♦"]
	var ranks := {11: "J", 12: "Q", 13: "K", 14: "A"}
	var rank_text: String = ranks.get(rank, str(rank))
	return "%s%s#%d" % [suits[suit], rank_text, copy_index]
