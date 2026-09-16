extends RefCounted
## Trick 单元测试：跟牌合法性（规则 §7.2）与赢家、收分（规则 §7.3）。级别 6、主花色红桃。

const LV := 6
const TR := Card.Suit.HEART
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_follow_count_cases(c)
	_follow_suit_cases(c)
	_winner_and_score_cases(c)


func _follow_count_cases(c: TestCheck) -> void:
	var hand: Array[Card] = [c.card(S, 5), c.card(D, 3)]
	var lead: Array[Card] = [c.card(S, 9)]
	c.check_false(Trick.can_follow(hand, lead, [c.card(S, 5), c.card(D, 3)], LV, TR), "§7.2 跟牌张数必须与首家相同")
	c.check_false(Trick.can_follow(hand, lead, [c.card(S, 10)], LV, TR), "§7.2 不能出手中没有的牌")


func _follow_suit_cases(c: TestCheck) -> void:
	var hand_two_spades: Array[Card] = [c.card(S, 5), c.card(S, 8), c.card(D, 3), c.card(H, 7)]
	var lead_single: Array[Card] = [c.card(S, 9)]
	c.check_true(Trick.can_follow(hand_two_spades, lead_single, [c.card(S, 5)], LV, TR), "§7.2 有同花色必须跟同花色")
	c.check_false(Trick.can_follow(hand_two_spades, lead_single, [c.card(D, 3)], LV, TR), "§7.2 有同花色却垫其他花色非法")

	var lead_stick: Array[Card] = [c.card(S, 9, 0), c.card(S, 9, 1)]
	c.check_true(Trick.can_follow(hand_two_spades, lead_stick, [c.card(S, 5), c.card(S, 8)], LV, TR), "§7.2 棒子轮跟两张同花色（可不出棒子）")
	c.check_false(Trick.can_follow(hand_two_spades, lead_stick, [c.card(S, 5), c.card(D, 3)], LV, TR), "§7.2 同花色足够时不许垫牌")

	var hand_one_spade: Array[Card] = [c.card(S, 5), c.card(D, 3), c.card(H, 7), c.card(CL, 9)]
	c.check_true(Trick.can_follow(hand_one_spade, lead_stick, [c.card(S, 5), c.card(D, 3)], LV, TR), "§7.2 同花色不足时可垫其他花色补齐")
	c.check_false(Trick.can_follow(hand_one_spade, lead_stick, [c.card(D, 3), c.card(CL, 9)], LV, TR), "§7.2 有同花色必须先跟（不能全垫）")

	var hand_level_suit: Array[Card] = [c.card(S, LV), c.card(D, 3), c.card(H, 7)]
	# 黑桃 6 是级牌（主牌），不算黑桃副牌，首家出黑桃时无须跟它
	c.check_true(Trick.can_follow(hand_level_suit, lead_single, [c.card(D, 3)], LV, TR), "§7.2 级牌是主牌，不算同花色副牌")

	var lead_trump: Array[Card] = [c.card(H, 10)]
	c.check_true(Trick.can_follow(hand_level_suit, lead_trump, [c.card(S, LV)], LV, TR), "§7.2 首家出主牌须跟主牌（级牌算主牌）")
	c.check_false(Trick.can_follow(hand_level_suit, lead_trump, [c.card(D, 3)], LV, TR), "§7.2 有主牌却垫副牌非法")


func _winner_and_score_cases(c: TestCheck) -> void:
	var trick := Trick.new(0, LV, TR)
	trick.add_play(0, [c.card(S, 9)])
	trick.add_play(1, [c.card(S, 14)])
	trick.add_play(2, [c.card(D, 5)])
	trick.add_play(3, [c.card(H, 3)])
	c.check_true(trick.is_complete(), "四家出完一轮结束")
	c.check_eq(trick.winner_seat(), 3, "§7.3 主牌单张杀副牌单张赢轮")
	c.check_eq(trick.score(), 5, "§7.3 赢家收走桌面分牌（5 分）")

	var trick2 := Trick.new(1, LV, TR)
	trick2.add_play(1, [c.card(S, 10, 0), c.card(S, 10, 1)])
	trick2.add_play(2, [c.card(S, 13), c.card(S, 14)])
	trick2.add_play(3, [c.card(H, 4, 0), c.card(H, 4, 1)])
	trick2.add_play(0, [c.card(D, 5), c.card(D, 8)])
	c.check_eq(trick2.winner_seat(), 3, "§7.3 主牌棒子杀副牌棒子赢轮")
	c.check_eq(trick2.score(), 35, "§7.3 桌面分牌合计 10+10+10+5=35")

	var trick3 := Trick.new(2, LV, TR)
	trick3.add_play(2, [c.card(S, 14)])
	trick3.add_play(3, [c.card(S, 5)])
	trick3.add_play(0, [c.card(S, 7)])
	trick3.add_play(1, [c.card(D, 10)])
	c.check_eq(trick3.winner_seat(), 2, "§7.3 无人压过则首家赢轮")
