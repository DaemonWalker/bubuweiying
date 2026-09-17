extends RefCounted
## AI 自动对局测试：4 个 HeuristicAI 无 UI 从发牌打到结算。
## 20 局（含首局、含王奖励进贡等变体）断言：不死锁、无非法动作、进入 SETTLEMENT、
## 手牌打空、分数守恒（§8：桌面分 + 底牌面值分 = 300）、S 计算正确。

const A := RoundState.ActionType
const P := RoundState.Phase
const ROUND_COUNT := 20
const MAX_STEPS := 3000  # 死锁保护上限（正常一局约 400 步）
const TOTAL_SCORE := 300
const BASE_SEED := 20261001
const SEED_STEP := 131


func run(c: TestCheck) -> void:
	for i in ROUND_COUNT:
		_run_round(c, _config_for(i), "AI 第%d局" % (i + 1))


# 变体覆盖：首局（i=0/10）、不同庄家方与级别、不同上局分数 S（含攻守易位区间）、王奖励进贡。
func _config_for(i: int) -> Dictionary:
	if i % 10 == 0:
		return {"is_first_round": true, "seed": BASE_SEED + i * SEED_STEP}
	var scores := [55, 75, 90, 100, 115, 130, 145, 160, 200]
	var levels := [3, 4, 5, 6, 7, 8, 9, 10]
	var config := {
		"is_first_round": false,
		"dealer_side": i % 2,
		"dealer_level": levels[i % levels.size()],
		"catcher_level": levels[(i * 3 + 1) % levels.size()],
		"tribute_score": scores[i % scores.size()],
		"seed": BASE_SEED + i * SEED_STEP,
	}
	if i % 3 == 0:
		config["tribute_bonus_big"] = 1
		config["tribute_bonus_small"] = i % 2
		config["tribute_bonus_active"] = true
	return config


func _run_round(c: TestCheck, config: Dictionary, label: String) -> void:
	var rs := RoundState.new(config)
	var ais: Array[HeuristicAI] = []
	for seat in RoundState.PLAYER_COUNT:
		var ai := HeuristicAI.new()
		ai.start_round(rs, seat)
		ais.append(ai)
	var illegal := 0
	var steps := 0
	while rs.get_phase() != P.SETTLEMENT and steps < MAX_STEPS and illegal == 0:
		steps += 1
		match rs.get_phase():
			P.DEALING:
				if rs.apply_action(0, {"type": A.DEAL}):
					for seat in RoundState.PLAYER_COUNT:
						illegal += _try_bid(rs, ais[seat], seat)
				else:
					illegal += 1
			P.BIDDING:
				var any_bid := false
				for seat in RoundState.PLAYER_COUNT:
					var action := ais[seat].decide_bid(rs, seat)
					if action.is_empty():
						continue
					if rs.apply_action(seat, action):
						any_bid = true
					else:
						illegal += 1
				if not any_bid and illegal == 0:
					if not rs.close_bidding():
						illegal += 1
			P.TRIBUTE, P.BOTTOM:
				illegal += _act_one(rs, ais)
			P.PLAYING:
				var seat := rs.get_current_seat()
				var action := ais[seat].decide_play(rs, seat)
				if rs.apply_action(seat, action):
					var played: Array[Card] = []
					played.assign(action.get("cards"))
					for ai in ais:
						ai.observe_play(seat, played)
				else:
					illegal += 1
	c.check_eq(illegal, 0, "%s 无非法动作" % label)
	c.check_true(steps < MAX_STEPS, "%s 不死锁（steps=%d）" % [label, steps])
	c.check_eq(rs.get_phase(), P.SETTLEMENT, "%s 进入 SETTLEMENT" % label)
	var hands_empty := true
	for seat in RoundState.PLAYER_COUNT:
		if not rs.get_hand(seat).is_empty():
			hands_empty = false
	c.check_true(hands_empty, "%s 手牌全部打空" % label)
	if rs.get_phase() == P.SETTLEMENT:
		var result := rs.get_result()
		var in_play: Array = result.get("in_play_scores", [0, 0])
		var bottom_score: int = result.get("bottom_score", 0)
		c.check_eq(in_play[0] + in_play[1] + bottom_score, TOTAL_SCORE,
			"%s §8 分数守恒：桌面分 + 底牌分 = 300" % label)
		var catcher := 1 - int(result.get("dealer_side", 0))
		var expected: int = int(in_play[catcher]) + (2 * bottom_score if result.get("kongdi", false) else 0)
		c.check_eq(result.get("catcher_score", -1), expected, "%s §8 S = 抓分方总分（含抠底翻倍）" % label)


func _try_bid(rs: RoundState, ai: HeuristicAI, seat: int) -> int:
	var action := ai.decide_bid(rs, seat)
	if action.is_empty():
		return 0
	return 0 if rs.apply_action(seat, action) else 1


# TRIBUTE / BOTTOM 阶段：找到当前有动作的座位，按动作类型路由到对应 decide_*。
func _act_one(rs: RoundState, ais: Array[HeuristicAI]) -> int:
	for seat in RoundState.PLAYER_COUNT:
		var actions := rs.get_available_actions(seat)
		if actions.is_empty():
			continue
		var type: int = actions[0].get("type")
		var action: Dictionary
		match type:
			A.TRIBUTE:
				action = ais[seat].decide_tribute_give(rs, seat)
			A.RETURN:
				action = ais[seat].decide_tribute_return(rs, seat)
			A.DISCARD_BOTTOM:
				action = ais[seat].decide_bottom(rs, seat)
			_:
				action = ais[seat].decide_bottom_joker(rs, seat)
		return 0 if rs.apply_action(seat, action) else 1
	return 1  # 无人可行动 = 状态机停滞
