class_name TestCheck
extends RefCounted
## 测试辅助：check_eq / check_true / check_false 断言与造牌快捷方法。

var passed := 0
var failed := 0


func check_eq(actual: Variant, expected: Variant, case_name: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		printerr("FAIL [%s] 期望 %s，实际 %s" % [case_name, expected, actual])


func check_true(cond: bool, case_name: String) -> void:
	check_eq(cond, true, case_name)


func check_false(cond: bool, case_name: String) -> void:
	check_eq(cond, false, case_name)


func card(suit: int, rank: int, copy_index: int = 0) -> Card:
	return Card.create(suit, rank, copy_index)


func small_joker(copy_index: int = 0) -> Card:
	return Card.create(Card.Suit.NONE, Card.RANK_SMALL_JOKER, copy_index)


func big_joker(copy_index: int = 0) -> Card:
	return Card.create(Card.Suit.NONE, Card.RANK_BIG_JOKER, copy_index)
