extends RefCounted
## Play 单元测试：牌型识别与大小比较（规则 §7）。默认级别 6、主花色红桃。

const LV := 6
const TR := Card.Suit.HEART
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_identify_cases(c)
	_trump_and_power_cases(c)
	_beats_cases(c)


func _identify_cases(c: TestCheck) -> void:
	c.check_eq(Play.identify([c.card(S, 5)]), Play.Type.SINGLE, "§7.1 单张")
	c.check_eq(Play.identify([c.card(S, 5, 0), c.card(S, 5, 1)]), Play.Type.STICK, "§7.1 棒子（同花色同点数两张）")
	c.check_eq(Play.identify([c.card(S, 5, 0), c.card(S, 5, 1), c.card(S, 5, 2)]), Play.Type.ROLLER, "§7.1 滚子")
	c.check_eq(Play.identify([c.card(S, 5), c.card(S, 7)]), Play.Type.INVALID, "§7.1 两张不同点数非法")
	c.check_eq(Play.identify([c.card(S, 5), c.card(D, 5)]), Play.Type.INVALID, "§7.1 同点数不同花色不是棒子")
	c.check_eq(Play.identify([c.card(S, 5, 0), c.card(S, 5, 1), c.card(S, 5, 2), c.card(S, 5, 0)]), Play.Type.INVALID, "§7.1 四张非法")
	c.check_eq(Play.identify([]), Play.Type.INVALID, "§7.1 空手非法")


func _trump_and_power_cases(c: TestCheck) -> void:
	c.check_true(Play.is_trump(c.big_joker(), LV, TR), "§3 大王是主牌")
	c.check_true(Play.is_trump(c.card(S, LV), LV, TR), "§3 副级牌是主牌")
	c.check_true(Play.is_trump(c.card(D, 2), LV, TR), "§3 副 2 是主牌")
	c.check_true(Play.is_trump(c.card(H, 3), LV, TR), "§3 主花色 3 是主牌")
	c.check_false(Play.is_trump(c.card(S, 14), LV, TR), "§3 副 A 不是主牌")
	var ordered: Array[Card] = [
		c.big_joker(), c.small_joker(), c.card(H, LV), c.card(S, LV),
		c.card(H, 2), c.card(S, 2), c.card(H, 14), c.card(H, 13), c.card(H, 3), c.card(S, 14),
	]
	var desc := true
	for i in range(ordered.size() - 1):
		if Play.power(ordered[i], LV, TR) <= Play.power(ordered[i + 1], LV, TR):
			desc = false
	c.check_true(desc, "§3 牌力序：大王>小王>主级>副级>主2>副2>主A>主K>主3>副A")
	c.check_eq(Play.power(c.card(S, LV), LV, TR), Play.power(c.card(D, LV), LV, TR), "§3 三个花色副级牌同级")


func _beats_cases(c: TestCheck) -> void:
	# 验收用例 1：主牌单张杀不了副牌棒子
	c.check_false(Play.beats(
		[c.card(S, 5, 0), c.card(S, 5, 1)],
		[c.card(H, 7), c.card(H, 9)], LV, TR),
		"§7.3 主牌单张不能杀副牌棒子（牌型不同判小）")
	c.check_false(Play.beats(
		[c.card(S, 5, 0), c.card(S, 5, 1)],
		[c.big_joker(0)], LV, TR),
		"§7.3 张数不同不能压")
	# 验收用例 2：主牌棒子能杀副牌棒子
	c.check_true(Play.beats(
		[c.card(S, 5, 0), c.card(S, 5, 1)],
		[c.card(H, 4, 0), c.card(H, 4, 1)], LV, TR),
		"§7.3 主牌棒子能杀副牌棒子")
	# 验收用例 3：垫牌判小
	c.check_false(Play.beats(
		[c.card(S, 14)],
		[c.card(D, 13)], LV, TR),
		"§7.3 垫牌判小（不同花色副牌互不比大小）")
	# 验收用例 4：单张轮主牌单张可杀副牌单张
	c.check_true(Play.beats(
		[c.card(S, 14)],
		[c.card(H, 3)], LV, TR),
		"§7.3 主牌单张可杀副牌单张")
	# 补充：同花色同牌型比大小
	c.check_true(Play.beats([c.card(S, 5)], [c.card(S, 14)], LV, TR), "§7.3 同花色副牌大杀小")
	c.check_false(Play.beats([c.card(S, 14)], [c.card(S, 5)], LV, TR), "§7.3 同花色小不能压大")
	c.check_true(Play.beats([c.card(H, 5)], [c.card(H, 14)], LV, TR), "§7.3 主牌内部大杀小")
	c.check_false(Play.beats([c.card(H, 5)], [c.card(S, 14)], LV, TR), "§7.3 副牌不能杀主牌")
	c.check_false(Play.beats([c.card(S, 14)], [c.card(D, 14)], LV, TR), "§7.3 不同花色副牌同点不比大小")
	# 主牌大牌序比较
	c.check_true(Play.beats(
		[c.card(H, LV, 0), c.card(H, LV, 1)],
		[c.big_joker(0), c.big_joker(1)], LV, TR),
		"§7.3 大王棒子杀主级牌棒子")
	# 牌型不同：两个单张赢不了棒子
	c.check_false(Play.beats(
		[c.card(S, 5, 0), c.card(S, 5, 1)],
		[c.card(S, 7), c.card(S, 9)], LV, TR),
		"§7.3 单张赢不了棒子（同花色也不行）")
	# 滚子：主牌滚子杀副牌滚子
	c.check_true(Play.beats(
		[c.card(S, 5, 0), c.card(S, 5, 1), c.card(S, 5, 2)],
		[c.big_joker(0), c.big_joker(1), c.big_joker(2)], LV, TR),
		"§7.3 主牌滚子杀副牌滚子")
