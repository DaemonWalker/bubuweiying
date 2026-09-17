extends RefCounted
## MatchState 单元测试：级别推进（§2）、庄家方轮换（§8/§10）、逢 10 必打与打过 10（§2）、
## 特殊结束（§9）、下局进贡参数（§5）、序列化往返。

const SIDE0 := 0
const SIDE1 := 1


func run(c: TestCheck) -> void:
	_initial_state(c)
	_level_and_dealer_progression(c)
	_must_hit_ten(c)
	_special_endings(c)
	_invalid_finish_round(c)
	_serialization_round_trip(c)


## 构造一局结果（字段对齐 RoundState.get_result()，结算部分直接走 Settlement.settle 保证真实）。
func _make_result(dealer_side: int, s: int, kongdi: bool, big: int, small: int,
		dry_pot: bool, dealer_level: int, catcher_level: int, dealer_seat: int = 0) -> Dictionary:
	var r := Settlement.settle(s, kongdi, big, small, dry_pot, dealer_level, catcher_level)
	r["catcher_score"] = s
	r["kongdi"] = kongdi
	r["dry_pot"] = dry_pot
	r["bottom_score"] = 0
	r["in_play_scores"] = [0, 0]
	r["next_dealer_side"] = (1 - dealer_side) if r["catcher_on_stage"] else dealer_side
	r["next_tribute"] = {
		"score": s, "bonus_big": big, "bonus_small": small,
		"bonus_active": not dry_pot and r["branch"] != 5 and not r["match_over"],
	}
	r["dealer_seat"] = dealer_seat
	r["dealer_side"] = dealer_side
	r["trump_suit"] = 0
	r["level"] = dealer_level
	return r


func _initial_state(c: TestCheck) -> void:
	var ms := MatchState.new(42)
	c.check_eq(ms.get_level(SIDE0), 3, "§2 初始级别 side0 = 3")
	c.check_eq(ms.get_level(SIDE1), 3, "§2 初始级别 side1 = 3")
	c.check_eq(ms.get_dealer_side(), MatchState.SIDE_NONE, "§4.2 首局庄家方未定（抢亮大王决定）")
	c.check_eq(ms.get_round_count(), 0, "初始已完成局数 = 0")
	c.check_false(ms.is_over(), "初始比赛未结束")
	c.check_eq(ms.get_winner(), MatchState.SIDE_NONE, "初始无胜方")
	c.check_eq(ms.next_tribute_count(), 0, "§5 首局不进贡")
	c.check_false(ms.next_tribute_reversed(), "首局无攻守易位")

	var config := ms.new_round_config()
	c.check_true(config["is_first_round"], "首局 config is_first_round = true")
	c.check_eq(config["seed"], 42, "首局种子 = base_seed")
	c.check_false(config.has("dealer_side"), "首局 config 不带 dealer_side")
	var round := ms.create_round()
	c.check_true(round != null, "首局 create_round 返回 RoundState")
	c.check_eq(round.get_phase(), RoundState.Phase.DEALING, "首局从 DEALING 开始")


func _level_and_dealer_progression(c: TestCheck) -> void:
	var ms := MatchState.new(7)

	# 第 1 局：side0 坐庄（首局抢亮结果），S=80 未抠底 → §8 分支7，庄家方升 1
	c.check_true(ms.finish_round(_make_result(SIDE0, 80, false, 0, 0, false, 3, 3, 2)), "第 1 局结果被接受")
	c.check_eq(ms.get_level(SIDE0), 4, "§8 分支7 庄家方升 1 级：3→4")
	c.check_eq(ms.get_level(SIDE1), 3, "§8 分支7 抓分方不升级")
	c.check_eq(ms.get_dealer_side(), SIDE0, "§8 分支7 庄家连任")
	c.check_eq(ms.get_dealer_seat(), 2, "记录上一局庄家座位")
	c.check_eq(ms.get_round_count(), 1, "已完成 1 局")
	c.check_eq(ms.next_tribute_count(), 1, "§5 S=80 下局进贡 1 张")
	c.check_false(ms.next_tribute_reversed(), "§5 S=80 不攻守易位")

	# 第 2 局：side0(4) 庄 side1(3)，S=150 抠底且底牌 1 大王 → 分支4，抓分方上台 +2
	c.check_true(ms.finish_round(_make_result(SIDE0, 150, true, 1, 0, false, 4, 3)), "第 2 局结果被接受")
	c.check_eq(ms.get_level(SIDE1), 5, "§8 分支4 抓分方上台 + 大王追加 2 级：3→5")
	c.check_eq(ms.get_level(SIDE0), 4, "§8 分支4 庄家方不升级")
	c.check_eq(ms.get_dealer_side(), SIDE1, "§8/§10 抓分方上台成为下局庄家方")
	c.check_eq(ms.next_tribute_count(), 3, "§5 S=150 进贡 1 张 + 大王加成 2 张")
	c.check_true(ms.next_tribute_reversed(), "§5 S=150 ∈ [120,150] 攻守易位")

	var config := ms.new_round_config()
	c.check_false(config["is_first_round"], "第 3 局 is_first_round = false")
	c.check_eq(config["dealer_side"], SIDE1, "第 3 局 config 庄家方 = side1")
	c.check_eq(config["dealer_level"], 5, "第 3 局 config 庄家方级别 = 5")
	c.check_eq(config["catcher_level"], 4, "第 3 局 config 抓分方级别 = 4")
	c.check_eq(config["tribute_score"], 150, "第 3 局 config 进贡分 = 150")
	c.check_eq(config["tribute_bonus_big"], 1, "第 3 局 config 底牌大王加成 = 1")
	c.check_true(config["tribute_bonus_active"], "分支4 后王奖励生效")
	c.check_eq(config["seed"], 9, "第 3 局种子 = base_seed + 已完成局数")

	# 第 3 局：side1(5) 庄 side0(4)，S=100 抠底 → 分支6，不上台不升级
	ms.finish_round(_make_result(SIDE1, 100, true, 0, 0, false, 5, 4))
	c.check_eq(ms.get_level(SIDE0), 4, "§8 分支6 双方不升级（side0）")
	c.check_eq(ms.get_level(SIDE1), 5, "§8 分支6 双方不升级（side1）")
	c.check_eq(ms.get_dealer_side(), SIDE1, "§8 分支6 庄家连任")

	# 第 4 局：side1(5) 庄 side0(4)，S=130 未抠底且底牌 1 大王 → 分支5，上台不升级、王奖励作废
	ms.finish_round(_make_result(SIDE1, 130, false, 1, 0, false, 5, 4))
	c.check_eq(ms.get_level(SIDE0), 4, "§8 分支5 抓分方上台但不升级")
	c.check_eq(ms.get_dealer_side(), SIDE0, "§8/§10 分支5 抓分方上台")
	c.check_eq(ms.next_tribute_count(), 1, "§8 分支5 王奖励作废，下局仅贡基础 1 张")
	c.check_true(ms.next_tribute_reversed(), "§5 S=130 ∈ [120,150] 攻守易位")
	c.check_false(ms.is_over(), "4 局后比赛未结束")


func _must_hit_ten(c: TestCheck) -> void:
	var ms := MatchState.new(1)
	# side0 在 9 级坐庄，S=80 未抠底且底牌 1 大王 → 分支7：9 + 1 + 2 = 12，落点拦截到 10
	ms.finish_round(_make_result(SIDE0, 80, false, 1, 0, false, 9, 4))
	c.check_eq(ms.get_level(SIDE0), 10, "§2 逢 10 必打：9 级 +3 落到 10 而不是跳过")
	c.check_false(ms.is_over(), "§2 升到 10 不算赢")

	# side0 在 10 级再坐庄，S=80 未抠底 → 分支7：10 级再升级 = 打过 10
	ms.finish_round(_make_result(SIDE0, 80, false, 0, 0, false, 10, 4))
	c.check_true(ms.is_over(), "§2/§9 在 10 级上再升级 = 打过 10，比赛结束")
	c.check_eq(ms.get_winner(), SIDE0, "§9 打过 10 的一方赢得整场")


func _special_endings(c: TestCheck) -> void:
	# 抓分方 0 分 → 庄家方赢整场
	var ms := MatchState.new(1)
	ms.finish_round(_make_result(SIDE0, 0, false, 0, 0, false, 3, 3))
	c.check_true(ms.is_over(), "§9 抓分方 0 分比赛立即结束")
	c.check_eq(ms.get_winner(), SIDE0, "§9 抓分方 0 分庄家方赢整场")
	c.check_eq(ms.get_round_count(), 1, "特殊结束仍计入局数")

	# 抓分方 300 分 → 抓分方赢整场
	ms = MatchState.new(1)
	ms.finish_round(_make_result(SIDE1, 300, true, 0, 0, false, 3, 3))
	c.check_true(ms.is_over(), "§9 抓分方 300 分比赛立即结束")
	c.check_eq(ms.get_winner(), SIDE0, "§9 抓分方 300 分抓分方赢整场（side1 庄 → side0 赢）")

	# 抠底且底牌 3 大王且 S≥120 → 抓分方赢整场
	ms = MatchState.new(1)
	ms.finish_round(_make_result(SIDE1, 200, true, 3, 0, false, 3, 3))
	c.check_true(ms.is_over(), "§9 抠出 3 大王且 S≥120 比赛立即结束")
	c.check_eq(ms.get_winner(), SIDE0, "§9 抠出 3 大王抓分方赢整场")

	# 结束后不再接受结果、不再创建新局
	c.check_false(ms.finish_round(_make_result(SIDE1, 80, false, 0, 0, false, 3, 3)), "比赛结束后 finish_round 拒绝")
	c.check_true(ms.create_round() == null, "比赛结束后 create_round 返回 null")
	c.check_true(ms.new_round_config().is_empty(), "比赛结束后 new_round_config 为空")
	c.check_eq(ms.get_round_count(), 1, "拒绝的结果不改变局数")


func _invalid_finish_round(c: TestCheck) -> void:
	var ms := MatchState.new(1)
	c.check_false(ms.finish_round({"dealer_side": 0}), "缺关键字段的结果被拒绝")
	c.check_false(ms.finish_round(_make_result(2, 80, false, 0, 0, false, 3, 3)), "非法 dealer_side 被拒绝")
	c.check_eq(ms.get_round_count(), 0, "非法结果不改变状态")
	c.check_eq(ms.get_level(SIDE0), 3, "非法结果不改变级别")


func _serialization_round_trip(c: TestCheck) -> void:
	var ms := MatchState.new(99)
	ms.finish_round(_make_result(SIDE0, 80, false, 0, 0, false, 3, 3, 2))
	ms.finish_round(_make_result(SIDE0, 150, true, 1, 0, false, 4, 3))

	var restored := MatchState.from_dict(ms.to_dict())
	c.check_eq(restored.to_dict(), ms.to_dict(), "序列化往返一致（to_dict 相等）")
	c.check_eq(restored.get_level(SIDE0), 4, "恢复后 side0 级别正确")
	c.check_eq(restored.get_level(SIDE1), 5, "恢复后 side1 级别正确")
	c.check_eq(restored.get_dealer_side(), SIDE1, "恢复后下局庄家方正确")
	c.check_eq(restored.get_dealer_seat(), 0, "恢复后庄家座位正确")
	c.check_eq(restored.get_round_count(), 2, "恢复后局数正确")
	c.check_eq(restored.next_tribute_count(), 3, "恢复后进贡张数正确")
	c.check_true(restored.next_tribute_reversed(), "恢复后攻守易位标记正确")

	# 经 JSON 文本往返（float 数值兼容）后仍一致
	var json_text: String = JSON.stringify(ms.to_dict())
	var from_json := MatchState.from_dict(JSON.parse_string(json_text) as Dictionary)
	c.check_eq(from_json.to_dict(), ms.to_dict(), "JSON 文本往返一致")

	# 恢复后可继续推进比赛
	c.check_true(from_json.finish_round(_make_result(SIDE1, 100, true, 0, 0, false, 5, 4)), "恢复后可继续接收局结果")
	c.check_eq(from_json.get_round_count(), 3, "恢复后局数继续累加")
	c.check_eq(from_json.new_round_config()["seed"], 102, "恢复后下一局种子 = base_seed + 局数")

	# 空存档恢复为初始状态
	var fresh := MatchState.from_dict({})
	c.check_eq(fresh.get_level(SIDE0), 3, "空字典恢复为初始级别")
	c.check_eq(fresh.get_round_count(), 0, "空字典恢复为 0 局")
	c.check_false(fresh.is_over(), "空字典恢复为未结束")
