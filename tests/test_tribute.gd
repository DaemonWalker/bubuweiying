extends RefCounted
## Tribute 单元测试：进贡数量与方向（规则 §5）、贡牌与还贡合法性。级别 6、主花色红桃。

const LV := 6
const TR := Card.Suit.HEART
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_count_cases(c)
	_tribute_legal_cases(c)
	_return_legal_cases(c)


func _count_cases(c: TestCheck) -> void:
	c.check_eq(Tribute.base_count(75), 2, "§5 75 分 → 1+⌈5/10⌉=2 张")
	c.check_eq(Tribute.base_count(70), 2, "§5 70 分 → 1+⌈10/10⌉=2 张")
	c.check_eq(Tribute.base_count(69), 3, "§5 向上取整：69 分 → 3 张")
	c.check_eq(Tribute.base_count(80), 1, "§5 80 分 → 1 张")
	c.check_eq(Tribute.base_count(115), 1, "§5 115 分 → 1 张")
	c.check_eq(Tribute.base_count(150), 1, "§5 150 分 → 1 张")
	c.check_eq(Tribute.base_count(160), 2, "§5 160 分 → 1+⌈10/10⌉=2 张")
	c.check_eq(Tribute.base_count(151), 2, "§5 151 分 → 2 张")
	c.check_true(Tribute.is_reversed(130), "§5 130 分 → 攻守易位方向反转")
	c.check_true(Tribute.is_reversed(120), "§5 120 分 → 方向反转")
	c.check_false(Tribute.is_reversed(115), "§5 115 分不反转")
	c.check_false(Tribute.is_reversed(151), "§5 151 分不反转")
	c.check_eq(Tribute.joker_bonus(1, 2), 4, "§5 底牌王加成：每张大王+2、小王+1")
	c.check_eq(Tribute.total_count(115, 1, 1, true), 4, "§5 115 分 + 底 1 大王 1 小王 → 1+2+1=4 张")
	c.check_eq(Tribute.total_count(115, 1, 1, false), 1, "§5/§8 王奖励未生效（干锅或分支5）不加成")


func _tribute_legal_cases(c: TestCheck) -> void:
	# 非分牌：红桃 A（主，114）> 黑桃 A（14）> 方块 9（9）；分牌黑桃 K、方块 5 不可贡
	var hand: Array[Card] = [
		c.card(H, 14), c.card(S, 14), c.card(D, 9), c.card(S, 13), c.card(D, 5),
	]
	c.check_true(Tribute.can_tribute(hand, [c.card(H, 14)], LV, TR), "§5 贡 1 张须为手中最大非分牌")
	c.check_false(Tribute.can_tribute(hand, [c.card(S, 14)], LV, TR), "§5 贡的不是最大牌则非法")
	c.check_false(Tribute.can_tribute(hand, [c.card(S, 13)], LV, TR), "§5 分牌不能进贡")
	c.check_true(Tribute.can_tribute(hand, [c.card(H, 14), c.card(S, 14)], LV, TR), "§5 贡 2 张须为最大的两张非分牌")
	c.check_false(Tribute.can_tribute(hand, [c.card(H, 14), c.card(D, 9)], LV, TR), "§5 贡 2 张时跳过次大牌非法")
	c.check_false(Tribute.can_tribute(hand, [c.card(H, 14), c.card(S, 14), c.card(D, 9), c.card(S, 13)], LV, TR),
		"§5 贡牌张数超过非分牌数非法")


func _return_legal_cases(c: TestCheck) -> void:
	c.check_true(Tribute.can_return([c.card(D, 9), c.card(S, 8)], LV, TR), "§5 还贡为非分牌副牌")
	c.check_false(Tribute.can_return([c.card(H, 3)], LV, TR), "§5 还贡不能是主牌")
	c.check_false(Tribute.can_return([c.card(S, 2)], LV, TR), "§5 还贡不能是 2（主牌）")
	c.check_false(Tribute.can_return([c.card(S, 10)], LV, TR), "§5 还贡不能是分牌")
	c.check_false(Tribute.can_return([c.card(CL, 5)], LV, TR), "§5 还贡不能是 5 分牌")
