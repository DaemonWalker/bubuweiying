extends RefCounted
## AI 自动对局测试：4 个 HeuristicAI 无 UI 从发牌打到结算（驱动见 tests/ai_round_driver.gd）。
## 20 局（含首局、含王奖励进贡等变体）断言：不死锁、无非法动作、进入 SETTLEMENT、
## 手牌打空、分数守恒（§8：桌面分 + 底牌面值分 = 300）、S 计算正确。

const Driver := preload("res://tests/ai_round_driver.gd")

const ROUND_COUNT := 20
const BASE_SEED := 20261001
const SEED_STEP := 131


func run(c: TestCheck) -> void:
	for i in ROUND_COUNT:
		var out := Driver.run_round(_config_for(i))
		Driver.check_round(c, out, "AI 第%d局" % (i + 1))


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
