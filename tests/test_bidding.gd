extends RefCounted
## Bidding 单元测试：优先级（规则 §4.4）、合法叫价枚举（§4.2、§4.3）、主花色确定。级别 6。

const LV := 6
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_priority_cases(c)
	_legal_bids_cases(c)
	_trump_suit_cases(c)


func _priority_cases(c: TestCheck) -> void:
	var l1 := Bidding.Bid.new(Bidding.Kind.LEVEL_1, S)
	var l2 := Bidding.Bid.new(Bidding.Kind.LEVEL_2, S)
	var l3 := Bidding.Bid.new(Bidding.Kind.LEVEL_3, S)
	var sj3 := Bidding.Bid.new(Bidding.Kind.SMALL_JOKERS_3, Bidding.SUIT_UNDECIDED)
	var bj3 := Bidding.Bid.new(Bidding.Kind.BIG_JOKERS_3, Bidding.SUIT_UNDECIDED)
	var first := Bidding.Bid.new(Bidding.Kind.FIRST_ROUND_JOKER, Bidding.SUIT_UNDECIDED)
	c.check_true(Bidding.beats(l1, null), "无人叫价时可亮主")
	c.check_true(Bidding.beats(l2, l1), "§4.3 级牌×2 可反 ×1")
	c.check_true(Bidding.beats(l3, l2), "§4.3 级牌×3 可反 ×2")
	c.check_true(Bidding.beats(l3, l1), "§4.3 级牌×3 可反 ×1")
	c.check_false(Bidding.beats(l1, l1), "§4.4 同数量级牌不构成有效反主")
	c.check_false(Bidding.beats(l1, l2), "§4.4 级牌×1 反不了 ×2")
	c.check_true(Bidding.beats(sj3, l3), "§4.4 小王×3 优于级牌×3")
	c.check_true(Bidding.beats(bj3, sj3), "§4.3 大王叫牌权优于小王")
	c.check_false(Bidding.beats(sj3, bj3), "§4.4 小王×3 反不了大王×3")
	c.check_false(Bidding.beats(bj3, first), "§4.2 首局大王亮主不可被反")
	c.check_false(Bidding.beats(first, first), "§4.2 首局大王亮主不可被反（含同种）")


func _legal_bids_cases(c: TestCheck) -> void:
	var hand: Array[Card] = [
		c.card(S, LV, 0), c.card(S, LV, 1), c.card(H, LV, 0),
		c.small_joker(0), c.small_joker(1), c.small_joker(2),
		c.card(D, 9),
	]
	var bids := Bidding.legal_bids(hand, LV, null, false)
	c.check_eq(bids.size(), 4, "§4.3 黑桃级牌×1/×2 + 红桃级牌×1 + 小王×3，共 4 种叫价")
	c.check_true(_has_bid(bids, Bidding.Kind.LEVEL_1, S), "§4.3 可亮 1 张黑桃级牌")
	c.check_true(_has_bid(bids, Bidding.Kind.LEVEL_2, S), "§4.3 可亮 2 张黑桃级牌")
	c.check_true(_has_bid(bids, Bidding.Kind.LEVEL_1, H), "§4.3 可亮 1 张红桃级牌")
	c.check_true(_has_bid(bids, Bidding.Kind.SMALL_JOKERS_3, Bidding.SUIT_UNDECIDED), "§4.3 3 张小王可亮")

	var over_l2 := Bidding.legal_bids(hand, LV, Bidding.Bid.new(Bidding.Kind.LEVEL_2, D), false)
	c.check_eq(over_l2.size(), 1, "§4.4 反级牌×2 需级牌×3 或王亮（手中仅小王×3 有效）")
	c.check_eq(over_l2[0].kind, Bidding.Kind.SMALL_JOKERS_3, "§4.4 压过级牌×2 的是小王×3")

	var over_sj3 := Bidding.legal_bids(hand, LV, Bidding.Bid.new(Bidding.Kind.SMALL_JOKERS_3, S), false)
	c.check_eq(over_sj3.size(), 0, "§4.4 小王×3 只能被大王×3 反（手中无）")

	var hand_big: Array[Card] = [c.big_joker(0), c.big_joker(1), c.big_joker(2)]
	c.check_eq(Bidding.legal_bids(hand_big, LV, Bidding.Bid.new(Bidding.Kind.SMALL_JOKERS_3, S), false).size(), 1,
		"§4.3 3 张大王可反小王×3")

	var hand_first: Array[Card] = [c.big_joker(0), c.card(S, LV)]
	var first_bids := Bidding.legal_bids(hand_first, LV, null, true)
	c.check_eq(first_bids.size(), 1, "§4.2 首局只能抢亮大王")
	c.check_eq(first_bids[0].kind, Bidding.Kind.FIRST_ROUND_JOKER, "§4.2 首局叫价种类为抢亮大王")
	var hand_no_joker: Array[Card] = [c.card(S, LV)]
	c.check_eq(Bidding.legal_bids(hand_no_joker, LV, null, true).size(), 0, "§4.2 首局无大王不能亮主")


func _trump_suit_cases(c: TestCheck) -> void:
	var after: Array[Card] = [c.small_joker(1), c.big_joker(1), c.card(CL, 4), c.card(S, 7)]
	c.check_eq(Bidding.first_round_trump_suit(after), CL, "§4.2 连续摸王则跳过，第一张花色牌定主")
	c.check_eq(Bidding.first_round_trump_suit([c.card(D, 4)]), D, "§4.2 下一张即花色牌")
	c.check_eq(Bidding.first_round_trump_suit([c.big_joker(2)]), Bidding.SUIT_UNDECIDED, "§4.2 之后全是王则未定")


func _has_bid(bids: Array[Bidding.Bid], kind: int, suit: int) -> bool:
	for bid in bids:
		if bid.kind == kind and bid.suit == suit:
			return true
	return false
