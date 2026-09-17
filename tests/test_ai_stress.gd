extends RefCounted
## 压力测试（step-08 验收）：AI 自动对局 100 局全部正常结束（同 test_ai_match 的标准断言），
## 配置覆盖首局、级别 3~10（含逢 10 必打）、S 0~250 含攻守易位区间与大额进贡、王奖励组合；
## 另跑 8 场完整比赛（MatchState 串联）直到 match_over，断言局数有界、finish_round 无拒绝、
## 胜方有效。边界规则（干锅、0 分、300 分、3 大王、逢 10 必打）的定向用例见
## test_bottom / test_round_state / test_settlement / test_match_state，与本套件一并运行。

const Driver := preload("res://tests/ai_round_driver.gd")

const STRESS_ROUNDS := 100
const MATCH_COUNT := 8
const MAX_MATCH_ROUNDS := 80  # 完整比赛局数上限（正常约 10~30 局）
const BASE_SEED := 770001
const SEED_STEP := 97


func run(c: TestCheck) -> void:
	_stress_rounds(c)
	_full_matches(c)


func _stress_rounds(c: TestCheck) -> void:
	for i in STRESS_ROUNDS:
		var out := Driver.run_round(_config_for(i))
		Driver.check_round(c, out, "压力 第%d局" % (i + 1))


# 变体覆盖：首局（每 10 局一局）、级别含 10（§2 逢 10 必打/打过 10）、
# S 含 0（§8 分支1 口径的极端进贡）与 250（大额进贡）、攻守易位区间 [120,150]、王奖励进贡。
func _config_for(i: int) -> Dictionary:
	if i % 10 == 0:
		return {"is_first_round": true, "seed": BASE_SEED + i * SEED_STEP}
	var scores := [0, 40, 75, 80, 115, 120, 145, 150, 160, 200, 250]
	var levels := [3, 4, 5, 6, 7, 8, 9, 10]
	var config := {
		"is_first_round": false,
		"dealer_side": i % 2,
		"dealer_level": levels[i % levels.size()],
		"catcher_level": levels[(i * 5 + 2) % levels.size()],
		"tribute_score": scores[i % scores.size()],
		"seed": BASE_SEED + i * SEED_STEP,
	}
	if i % 3 == 0:
		config["tribute_bonus_big"] = i % 3
		config["tribute_bonus_small"] = (i / 3) % 3
		config["tribute_bonus_active"] = true
	return config


func _full_matches(c: TestCheck) -> void:
	for m in MATCH_COUNT:
		var ms := MatchState.new(BASE_SEED + m * 977)
		var rounds := 0
		var rejected := 0
		while not ms.is_over() and rounds < MAX_MATCH_ROUNDS and rejected == 0:
			var out := Driver.run_round(ms.new_round_config())
			rounds += 1
			var rs: RoundState = out.get("rs")
			if int(out.get("illegal", -1)) != 0 or rs.get_phase() != RoundState.Phase.SETTLEMENT:
				rejected += 1
			elif not ms.finish_round(rs.get_result()):
				rejected += 1
		var label := "比赛%d" % (m + 1)
		c.check_eq(rejected, 0, "%s 局内无非法动作、推进无拒绝" % label)
		c.check_true(ms.is_over(), "%s §2/§9 在 %d 局上限内分出胜负（实际 %d 局）" % [
			label, MAX_MATCH_ROUNDS, rounds])
		c.check_true(ms.get_winner() in [0, 1], "%s 胜方有效" % label)
