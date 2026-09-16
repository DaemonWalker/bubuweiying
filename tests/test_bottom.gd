extends RefCounted
## Bottom 单元测试：扣王、补偿捡牌与干锅（规则 §6）。级别 6、主花色红桃。

const LV := 6
const TR := Card.Suit.HEART
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_discard_cases(c)
	_compensation_cases(c)
	_dry_pot_cases(c)


func _discard_cases(c: TestCheck) -> void:
	var hand: Array[Card] = [c.big_joker(0), c.small_joker(0), c.card(S, 9)]
	c.check_true(Bottom.can_discard_jokers(hand, [c.big_joker(0)]), "§6 有大王先扣大王")
	c.check_false(Bottom.can_discard_jokers(hand, [c.small_joker(0)]), "§6 有大王时不能先扣小王")
	c.check_true(Bottom.can_discard_jokers(hand, [c.big_joker(0), c.small_joker(0)]), "§6 大王小王一起扣合法（张数不限）")
	c.check_false(Bottom.can_discard_jokers(hand, [c.card(S, 9)]), "§6 只能扣王")
	c.check_false(Bottom.can_discard_jokers(hand, [c.big_joker(1)]), "§6 不能扣手中没有的王")
	var hand_no_big: Array[Card] = [c.small_joker(0), c.small_joker(1), c.card(S, 9)]
	c.check_true(Bottom.can_discard_jokers(hand_no_big, [c.small_joker(0)]), "§6 没大王才能扣小王")
	c.check_false(Bottom.can_discard_jokers(hand_no_big, []), "§6 空扣非法")


func _compensation_cases(c: TestCheck) -> void:
	# 底牌：黑桃 A(14)、黑桃 9(9)、方块 8(8)、红桃 3(主，103)、方块 5(分)、黑桃 5(分)
	var bottom: Array[Card] = [
		c.card(S, 14), c.card(S, 9), c.card(D, 8), c.card(H, 3), c.card(D, 5), c.card(S, 5),
	]
	c.check_true(Bottom.can_pick_compensation(bottom, [c.card(D, 8)], LV, TR), "§6 扣王补偿捡最小非分牌")
	c.check_false(Bottom.can_pick_compensation(bottom, [c.card(S, 14)], LV, TR), "§6 补偿必须捡最小牌")
	c.check_false(Bottom.can_pick_compensation(bottom, [c.card(D, 5)], LV, TR), "§6 补偿不能捡分牌")
	c.check_true(Bottom.can_pick_compensation(bottom, [c.card(D, 8), c.card(S, 9)], LV, TR), "§6 扣 2 王捡 2 张最小")
	c.check_false(Bottom.can_pick_compensation(bottom, [c.card(D, 8), c.card(H, 3)], LV, TR), "§6 扣 2 王跳过次小牌非法")
	c.check_false(Bottom.can_pick_compensation(bottom, [c.card(CL, 3)], LV, TR), "§6 补偿牌必须在底牌中")


func _dry_pot_cases(c: TestCheck) -> void:
	var all_trump: Array[Card] = [
		c.card(H, 3), c.card(H, 9), c.card(S, LV), c.card(D, 2), c.big_joker(0), c.card(H, 14),
	]
	c.check_true(Bottom.is_dry_pot(all_trump, LV, TR), "§6 底牌全是主牌 → 干锅")
	var all_side: Array[Card] = [
		c.card(S, 3), c.card(S, 4), c.card(D, 5), c.card(CL, 9), c.card(S, 10), c.card(D, 13),
	]
	c.check_true(Bottom.is_dry_pot(all_side, LV, TR), "§6 底牌全是副牌 → 干锅（含分牌也算副牌）")
	var mixed: Array[Card] = [
		c.card(H, 3), c.card(S, 3), c.card(D, 5), c.card(CL, 9), c.card(S, 10), c.card(D, 13),
	]
	c.check_false(Bottom.is_dry_pot(mixed, LV, TR), "§6 底牌主副混合 → 非干锅")
	c.check_false(Bottom.is_dry_pot([], LV, TR), "§6 空底牌不干锅")
