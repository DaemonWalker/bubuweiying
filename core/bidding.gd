class_name Bidding
extends RefCounted
## 亮主/反主：叫价表示、优先级比较（规则 §4.4）、合法叫价枚举、主花色确定（规则 §4）。

## 叫价种类：级牌 ×1/×2/×3、小王×3、大王×3、首局抢亮大王。
enum Kind { NONE, LEVEL_1, LEVEL_2, LEVEL_3, SMALL_JOKERS_3, BIG_JOKERS_3, FIRST_ROUND_JOKER }

## 未指定花色：王亮叫价的花色由叫价者选定；首局大王亮主的花色由后续摸牌确定。
const SUIT_UNDECIDED := -1


## 一次叫价。kind 为叫价种类；suit 对级牌叫价 = 所亮级牌的花色（即主花色），
## 对王亮 = 叫价者指定的主花色，未定时为 SUIT_UNDECIDED。
class Bid:
	extends RefCounted
	var kind: int
	var suit: int

	func _init(p_kind: int, p_suit: int) -> void:
		kind = p_kind
		suit = p_suit


## 规则 §4.4 优先级：大王×3 > 小王×3 > 级牌×3 > 级牌×2 > 级牌×1；
## 首局大王亮主不可被反（§4.2），优先级最高。
static func _priority(kind: int) -> int:
	match kind:
		Kind.LEVEL_1:
			return 1
		Kind.LEVEL_2:
			return 2
		Kind.LEVEL_3:
			return 3
		Kind.SMALL_JOKERS_3:
			return 4
		Kind.BIG_JOKERS_3:
			return 5
		Kind.FIRST_ROUND_JOKER:
			return 6
	return 0


static func _level_bid_count(kind: int) -> int:
	match kind:
		Kind.LEVEL_1:
			return 1
		Kind.LEVEL_2:
			return 2
		Kind.LEVEL_3:
			return 3
	return 0


## new_bid 是否能压过 current。同数量级牌不构成有效反主（§4.4），故严格大于。
## current 为 null 表示尚未有人叫价。
static func beats(new_bid: Bid, current: Bid) -> bool:
	if new_bid == null or new_bid.kind == Kind.NONE:
		return false
	if current == null or current.kind == Kind.NONE:
		return true
	return _priority(new_bid.kind) > _priority(current.kind)


## 枚举手牌中所有能压过 current 的合法叫价（规则 §4.2、§4.3）。
## 首局（is_first_round）只能抢亮大王；否则可亮当前级牌（按手中同花色级牌数 ×1/×2/×3）
## 或王亮（3 张小王 / 3 张大王，suit 为 SUIT_UNDECIDED，由叫价者选定）。
static func legal_bids(hand: Array[Card], level: int, current: Bid, is_first_round: bool) -> Array[Bid]:
	var bids: Array[Bid] = []
	if is_first_round:
		for card in hand:
			if card.is_big_joker():
				_append_if_beats(bids, Bid.new(Kind.FIRST_ROUND_JOKER, SUIT_UNDECIDED), current)
				break
		return bids
	var level_by_suit := {}
	var small_jokers := 0
	var big_jokers := 0
	for card in hand:
		if card.is_big_joker():
			big_jokers += 1
		elif card.is_small_joker():
			small_jokers += 1
		elif card.rank == level:
			level_by_suit[card.suit] = level_by_suit.get(card.suit, 0) + 1
	for suit in level_by_suit:
		var count: int = level_by_suit[suit]
		for kind in [Kind.LEVEL_1, Kind.LEVEL_2, Kind.LEVEL_3]:
			if count >= _level_bid_count(kind):
				_append_if_beats(bids, Bid.new(kind, suit), current)
	if small_jokers == DECK_JOKER_COPIES:
		_append_if_beats(bids, Bid.new(Kind.SMALL_JOKERS_3, SUIT_UNDECIDED), current)
	if big_jokers == DECK_JOKER_COPIES:
		_append_if_beats(bids, Bid.new(Kind.BIG_JOKERS_3, SUIT_UNDECIDED), current)
	return bids


const DECK_JOKER_COPIES := 3


static func _append_if_beats(bids: Array[Bid], bid: Bid, current: Bid) -> void:
	if beats(bid, current):
		bids.append(bid)


## 首局大王亮主的主花色（规则 §4.2）：亮出大王后摸到的第一张花色牌的花色，
## 连续摸到王则跳过。cards_after 为亮主者在该大王之后摸到的牌（按摸牌顺序）；
## 之后无花色牌时返回 SUIT_UNDECIDED。
static func first_round_trump_suit(cards_after: Array[Card]) -> int:
	for card in cards_after:
		if not card.is_joker():
			return card.suit
	return SUIT_UNDECIDED
