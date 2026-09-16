extends RefCounted
## Card 单元测试。


func run(c: TestCheck) -> void:
	c.check_eq(c.card(Card.Suit.SPADE, 5).score_value(), 5, "§1 5 是 5 分牌")
	c.check_eq(c.card(Card.Suit.HEART, 10).score_value(), 10, "§1 10 是 10 分牌")
	c.check_eq(c.card(Card.Suit.CLUB, 13).score_value(), 10, "§1 K 是 10 分牌")
	c.check_eq(c.card(Card.Suit.DIAMOND, 14).score_value(), 0, "§1 A 不是分牌")
	c.check_eq(c.big_joker().score_value(), 0, "§1 大王不是分牌")
	c.check_true(c.big_joker().is_joker(), "大王是王")
	c.check_true(c.small_joker().is_small_joker(), "小王识别")
	c.check_false(c.card(Card.Suit.SPADE, 2).is_joker(), "2 不是王")
	c.check_true(c.card(Card.Suit.SPADE, 5, 0).same_card(c.card(Card.Suit.SPADE, 5, 1)), "同花色同点数算同牌")
	c.check_false(c.card(Card.Suit.SPADE, 5, 0).is_identical(c.card(Card.Suit.SPADE, 5, 1)), "副本序号区分两张相同牌")
	var hand: Array[Card] = [c.card(Card.Suit.SPADE, 5, 1)]
	c.check_true(Card.contains_identical(hand, c.card(Card.Suit.SPADE, 5, 1)), "contains_identical 命中")
	c.check_false(Card.contains_identical(hand, c.card(Card.Suit.SPADE, 5, 0)), "contains_identical 区分副本")
