extends RefCounted
## AI 自动对局驱动（test_ai_match / test_ai_stress 共用）：4 个 HeuristicAI 无 UI
## 打完一局，返回 {"rs": RoundState, "illegal": int, "steps": int}；
## check_round 提供一局的标准断言（无非法动作、不死锁、进 SETTLEMENT、手牌打空、
## 分数守恒 §8、S 计算正确）。

const A := RoundState.ActionType
const P := RoundState.Phase
const MAX_STEPS := 3000  # 死锁保护上限（正常一局约 400 步）
const TOTAL_SCORE := 300


static func run_round(config: Dictionary, max_steps := MAX_STEPS) -> Dictionary:
	var rs := RoundState.new(config)
	var ais: Array[HeuristicAI] = []
	for seat in RoundState.PLAYER_COUNT:
		var ai := HeuristicAI.new()
		ai.start_round(rs, seat)
		ais.append(ai)
	var illegal := 0
	var steps := 0
	while rs.get_phase() != P.SETTLEMENT and steps < max_steps and illegal == 0:
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
	return {"rs": rs, "illegal": illegal, "steps": steps}


# 一局结束的标准断言（6 条）；label 前缀区分用例。
static func check_round(c: TestCheck, out: Dictionary, label: String,
		max_steps := MAX_STEPS) -> void:
	var rs: RoundState = out.get("rs")
	c.check_eq(int(out.get("illegal", -1)), 0, "%s 无非法动作" % label)
	c.check_true(int(out.get("steps", max_steps)) < max_steps,
		"%s 不死锁（steps=%d）" % [label, int(out.get("steps", -1))])
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


static func _try_bid(rs: RoundState, ai: HeuristicAI, seat: int) -> int:
	var action := ai.decide_bid(rs, seat)
	if action.is_empty():
		return 0
	return 0 if rs.apply_action(seat, action) else 1


# TRIBUTE / BOTTOM 阶段：找到当前有动作的座位，按动作类型路由到对应 decide_*。
static func _act_one(rs: RoundState, ais: Array[HeuristicAI]) -> int:
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
