extends RefCounted
## Settlement 单元测试：结算矩阵（规则 §8 全部 7 分支）、特殊结束（§9）、升级应用（§2）。

const DEALER := Settlement.Winner.DEALER_SIDE
const CATCHER := Settlement.Winner.CATCHER_SIDE
const NONE := Settlement.Winner.NONE


func run(c: TestCheck) -> void:
	_special_ending_cases(c)
	_branch_4_and_5_cases(c)
	_branch_6_and_7_cases(c)
	_level_up_cases(c)


func _special_ending_cases(c: TestCheck) -> void:
	var r := Settlement.settle(0, false, 0, 0, false, 5, 7)
	c.check_eq(r.branch, 1, "§8 分支1：抓分方 0 分")
	c.check_true(r.match_over, "§9 抓分方 0 分立即结束整场")
	c.check_eq(r.match_winner, DEALER, "§9 抓分方 0 分庄家方赢整场")

	r = Settlement.settle(300, true, 0, 0, false, 5, 7)
	c.check_eq(r.branch, 2, "§8 分支2：抓分方 300 分")
	c.check_true(r.match_over, "§9 抓分方 300 分立即结束整场")
	c.check_eq(r.match_winner, CATCHER, "§9 抓分方 300 分抓分方赢整场")

	r = Settlement.settle(200, true, 3, 0, false, 5, 7)
	c.check_eq(r.branch, 3, "§8 分支3：抠底且底牌 3 大王且 S≥120")
	c.check_true(r.match_over, "§9 抠出 3 大王立即结束整场")
	c.check_eq(r.match_winner, CATCHER, "§9 抠出 3 大王抓分方赢整场")

	r = Settlement.settle(100, true, 3, 0, false, 5, 7)
	c.check_eq(r.branch, 6, "§8 底牌 3 大王但 S<120 不构成特殊结束，落分支6")
	c.check_false(r.match_over, "§9 S<120 时 3 大王不终结比赛")

	r = Settlement.settle(200, false, 3, 0, false, 5, 7)
	c.check_eq(r.branch, 5, "§8 未抠底时 3 大王不构成特殊结束，落分支5")
	c.check_false(r.match_over, "§9 未抠底时 3 大王不终结比赛")


func _branch_4_and_5_cases(c: TestCheck) -> void:
	var r := Settlement.settle(150, true, 1, 1, false, 5, 7)
	c.check_eq(r.branch, 4, "§8 分支4：S≥120 且抠底")
	c.check_true(r.catcher_on_stage, "§8 分支4 抓分方上台")
	c.check_eq(r.catcher_level, 10, "§8 分支4 底牌王追加升级：7 + 大王2 + 小王1 = 10")
	c.check_false(r.match_over, "§2 升到 10 不算赢，需在 10 级上再升级")
	c.check_eq(r.dealer_level, 5, "§8 分支4 庄家方不升级")

	r = Settlement.settle(150, true, 1, 1, true, 5, 7)
	c.check_eq(r.branch, 4, "§8 干锅局仍走分支4")
	c.check_eq(r.catcher_level, 7, "§8 干锅局王追加升级作废")

	r = Settlement.settle(150, true, 1, 0, false, 5, 10)
	c.check_eq(r.branch, 4, "§8 分支4（抓分方在 10 级）")
	c.check_true(r.match_over, "§2/§9 10 级再升级 = 打过 10 赢整场")
	c.check_eq(r.match_winner, CATCHER, "§9 抓分方打过 10 赢整场")

	r = Settlement.settle(150, true, 0, 0, false, 5, 7)
	c.check_eq(r.branch, 4, "§8 分支4：抠底但底牌无王")
	c.check_eq(r.catcher_level, 7, "§8 分支4 底牌无王不追加升级")

	r = Settlement.settle(130, false, 2, 0, false, 5, 7)
	c.check_eq(r.branch, 5, "§8 分支5：S≥120 未抠底")
	c.check_true(r.catcher_on_stage, "§8 分支5 抓分方上台")
	c.check_eq(r.catcher_level, 7, "§8 分支5 不升级，底牌王奖励作废")


func _branch_6_and_7_cases(c: TestCheck) -> void:
	var r := Settlement.settle(100, true, 1, 0, false, 5, 7)
	c.check_eq(r.branch, 6, "§8 分支6：S<120 且抠底")
	c.check_false(r.catcher_on_stage, "§8 分支6 抓分方不上台")
	c.check_eq(r.dealer_level, 5, "§8 分支6 庄家方不升级")
	c.check_eq(r.catcher_level, 7, "§8 分支6 抓分方不升级")

	r = Settlement.settle(80, false, 1, 1, false, 5, 7)
	c.check_eq(r.branch, 7, "§8 分支7：S<120 未抠底（保底）")
	c.check_false(r.catcher_on_stage, "§8 分支7 抓分方不上台")
	c.check_eq(r.dealer_level, 9, "§8 分支7 庄家方升 1 级 + 王追加：5+1+2+1=9")

	r = Settlement.settle(80, false, 1, 1, true, 5, 7)
	c.check_eq(r.dealer_level, 6, "§8 干锅局分支7 只升 1 级，王追加作废")

	r = Settlement.settle(80, false, 0, 1, false, 9, 7)
	c.check_eq(r.dealer_level, 10, "§2 从 9 升 2 级落点不跳过 10")
	c.check_false(r.match_over, "§2 升到 10 不算赢")

	r = Settlement.settle(80, false, 0, 0, false, 10, 7)
	c.check_eq(r.branch, 7, "§8 分支7（庄家方在 10 级）")
	c.check_true(r.match_over, "§9 庄家方 10 级再升级赢整场")
	c.check_eq(r.match_winner, DEALER, "§9 庄家方打过 10 赢整场")


func _level_up_cases(c: TestCheck) -> void:
	var up := Settlement.apply_level_up(3, 1)
	c.check_eq(up.level, 4, "§2 正常升 1 级")
	c.check_false(up.match_won, "§2 普通升级不终结比赛")
	up = Settlement.apply_level_up(9, 5)
	c.check_eq(up.level, 10, "§2 从 9 升任意级数都落到 10")
	c.check_false(up.match_won, "§2 落 10 不算打过 10")
	up = Settlement.apply_level_up(10, 1)
	c.check_true(up.match_won, "§2 10 级上再升级 = 打过 10")
