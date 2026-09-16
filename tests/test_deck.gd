extends RefCounted
## Deck 单元测试。


func run(c: TestCheck) -> void:
	var cards := Deck.build()
	c.check_eq(cards.size(), 162, "§1 3 副牌共 162 张")
	var counts := {}
	for card in cards:
		var key := "%d_%d" % [card.suit, card.rank]
		counts[key] = counts.get(key, 0) + 1
	c.check_eq(counts.size(), 54, "§1 一副 54 种牌")
	var all_three := true
	for key in counts:
		if counts[key] != 3:
			all_three = false
	c.check_true(all_three, "§1 每种牌恰好 3 个副本")

	var dealt := Deck.deal(Deck.shuffled(42))
	var hands: Array = dealt["hands"]
	c.check_eq(hands.size(), 4, "4 家")
	for hand in hands:
		c.check_eq((hand as Array).size(), 39, "§1 每人 39 张")
	c.check_eq((dealt["bottom"] as Array).size(), 6, "§1 底牌 6 张")

	var seen := {}
	for hand in hands:
		for card in hand:
			seen["%d_%d_%d" % [card.suit, card.rank, card.copy_index]] = true
	for card in dealt["bottom"]:
		seen["%d_%d_%d" % [card.suit, card.rank, card.copy_index]] = true
	c.check_eq(seen.size(), 162, "发牌后 162 张无重复无遗漏")

	var a := Deck.shuffled(7)
	var b := Deck.shuffled(7)
	var identical := true
	for i in a.size():
		if not a[i].is_identical(b[i]):
			identical = false
	c.check_true(identical, "同 seed 洗牌结果可复现")
