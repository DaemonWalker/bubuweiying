class_name Settlement
extends RefCounted
## 一局结算矩阵（规则 §8 全部 7 分支）、特殊结束（规则 §9）与升级应用（规则 §2）。

const WIN_SCORE := 120
const TOTAL_SCORE := 300
const BIG_JOKER_LEVEL_BONUS := 2
const SMALL_JOKER_LEVEL_BONUS := 1
const MAX_LEVEL := 10

enum Winner { NONE, DEALER_SIDE, CATCHER_SIDE }


## 升级应用（规则 §2）：落点不得跳过 3 或 10（级别从 3 起单调递增，故只需拦截 10）；
## 在 10 级上再次升级 = "打过 10"，赢得整场比赛。
## 返回 {"level": int, "match_won": bool}。
static func apply_level_up(level: int, steps: int) -> Dictionary:
	var won := level == MAX_LEVEL and steps > 0
	return {"level": mini(level + steps, MAX_LEVEL), "match_won": won}


## 一局结算。
## s：抓分方总分（含抠底翻倍）；kongdi：抠底（最后一轮抓分方赢）；
## bottom_big_jokers / bottom_small_jokers：底牌中扣入的大/小王数；
## dry_pot：干锅（分支 4、7 的王追加升级作废，规则 §6.4、§8）；
## dealer_level / catcher_level：双方当前级别。
## 返回 Dictionary：
## - branch: 1~7，规则 §8 分支号
## - match_over / match_winner（Winner 枚举）：§9 特殊结束或"打过 10"
## - catcher_on_stage：抓分方是否上台（成为下局庄家方）
## - dealer_level / catcher_level：结算后的双方级别
static func settle(s: int, kongdi: bool, bottom_big_jokers: int, bottom_small_jokers: int,
		dry_pot: bool, dealer_level: int, catcher_level: int) -> Dictionary:
	var result := {
		"branch": 0,
		"match_over": false,
		"match_winner": Winner.NONE,
		"catcher_on_stage": false,
		"dealer_level": dealer_level,
		"catcher_level": catcher_level,
	}
	var joker_bonus := 0 if dry_pot else (
		bottom_big_jokers * BIG_JOKER_LEVEL_BONUS + bottom_small_jokers * SMALL_JOKER_LEVEL_BONUS)
	if s == 0:
		# 规则 §8 分支1：抓分方 0 分，庄家方立即赢得整场
		result.branch = 1
		_set_match_winner(result, Winner.DEALER_SIDE)
	elif s == TOTAL_SCORE:
		# 规则 §8 分支2：抓分方 300 分，抓分方立即赢得整场
		result.branch = 2
		_set_match_winner(result, Winner.CATCHER_SIDE)
	elif kongdi and bottom_big_jokers == 3 and s >= WIN_SCORE:
		# 规则 §8 分支3：抠出底牌 3 大王且 S≥120，抓分方立即赢得整场
		result.branch = 3
		_set_match_winner(result, Winner.CATCHER_SIDE)
	elif s >= WIN_SCORE:
		result.catcher_on_stage = true
		if kongdi:
			# 规则 §8 分支4：抠底成功，抓分方上台 + 底牌王追加升级
			result.branch = 4
			if joker_bonus > 0:
				var up := apply_level_up(catcher_level, joker_bonus)
				result.catcher_level = up.level
				if up.match_won:
					_set_match_winner(result, Winner.CATCHER_SIDE)
		else:
			# 规则 §8 分支5：≥120 未抠底，上台不升级，底牌王奖励作废
			result.branch = 5
	elif kongdi:
		# 规则 §8 分支6：<120 且抠底，抓分方不上台，庄家连任，双方不升级
		result.branch = 6
	else:
		# 规则 §8 分支7：<120 未抠底（保底），庄家方升 1 级 + 底牌王追加升级
		result.branch = 7
		var up := apply_level_up(dealer_level, 1 + joker_bonus)
		result.dealer_level = up.level
		if up.match_won:
			_set_match_winner(result, Winner.DEALER_SIDE)
	return result


static func _set_match_winner(result: Dictionary, winner: int) -> void:
	result.match_over = true
	result.match_winner = winner
