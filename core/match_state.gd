class_name MatchState
extends RefCounted
## 整场比赛（规则 §2、§8、§9）：两队级别、庄家方、局序、下局进贡参数、比赛结束判定。
## 只持有局间状态（供存档）；局内流程由 RoundState 负责，每局结束后把
## RoundState.get_result() 交给 finish_round() 推进比赛。
## 庄家轮换（规则 §10 已定稿）：庄家方由上局结算唯一确定（result.next_dealer_side），
## 庄家方内部谁坐庄由该局 RoundState 在亮主阶段结束后决定，本类不介入。

const FIRST_LEVEL := 3  # 规则 §2：两队初始级别均为 3
const SIDE_NONE := -1   # 庄家方/胜方未定
const SAVE_VERSION := 1

var _levels: Array[int] = [FIRST_LEVEL, FIRST_LEVEL]  # 索引即 side（0={0,2}，1={1,3}）
var _dealer_side := SIDE_NONE  # 下局庄家方；首局未定（抢亮大王/翻底牌决定，规则 §4.2）
var _dealer_seat := -1  # 上一局庄家座位；尚无已完成局时为 -1
var _round_count := 0  # 已完成局数
var _base_seed := 1  # 洗牌种子基数，第 n 局（0 起）用 base_seed + n
var _next_tribute := {"score": 0, "bonus_big": 0, "bonus_small": 0, "bonus_active": false}
var _match_over := false
var _winner := SIDE_NONE


## 新比赛。base_seed 为洗牌种子基数（每局种子 = base_seed + 已完成局数）。
func _init(base_seed: int = 1) -> void:
	_base_seed = base_seed


## 指定方（0/1）的当前级别。
func get_level(side: int) -> int:
	return _levels[side]


## 下局庄家方（0/1）；首局为 SIDE_NONE（由抢亮大王/翻底牌决定，规则 §4.2）。
func get_dealer_side() -> int:
	return _dealer_side


## 上一局庄家座位（0~3）；尚无已完成局时为 -1。
func get_dealer_seat() -> int:
	return _dealer_seat


## 已完成局数。
func get_round_count() -> int:
	return _round_count


## 比赛是否已结束（规则 §9 特殊结束或打过 10）。
func is_over() -> bool:
	return _match_over


## 胜方（0/1）；未结束为 SIDE_NONE。
func get_winner() -> int:
	return _winner


## 下局进贡参数：{score 上局抓分方总分, bonus_big/bonus_small 底牌大/小王数, bonus_active 王奖励是否生效}。
func get_next_tribute() -> Dictionary:
	return _next_tribute.duplicate()


## 下局进贡张数（规则 §5，含生效时的底牌王加成）；首局为 0。
func next_tribute_count() -> int:
	if _round_count == 0:
		return 0
	return Tribute.total_count(
		_next_tribute["score"], _next_tribute["bonus_big"],
		_next_tribute["bonus_small"], _next_tribute["bonus_active"])


## 下局进贡是否攻守易位（规则 §5：上局抓分方得分 120~150）。
func next_tribute_reversed() -> bool:
	return _round_count > 0 and Tribute.is_reversed(_next_tribute["score"])


## 下一局的 RoundState 构造参数；比赛已结束时返回空 Dictionary。
func new_round_config() -> Dictionary:
	if _match_over:
		return {}
	var config := {
		"seed": _base_seed + _round_count,
		"is_first_round": _round_count == 0,
	}
	if _round_count > 0:
		config["dealer_side"] = _dealer_side
		config["dealer_level"] = _levels[_dealer_side]
		config["catcher_level"] = _levels[1 - _dealer_side]
		config["tribute_score"] = _next_tribute["score"]
		config["tribute_bonus_big"] = _next_tribute["bonus_big"]
		config["tribute_bonus_small"] = _next_tribute["bonus_small"]
		config["tribute_bonus_active"] = _next_tribute["bonus_active"]
	return config


## 创建下一局 RoundState；比赛已结束时返回 null。
func create_round() -> RoundState:
	if _match_over:
		return null
	return RoundState.new(new_round_config())


## 接收一局结果（RoundState.get_result()），更新级别/庄家方/进贡参数并判定比赛结束。
## 返回 false 表示未接受（比赛已结束或结果缺关键字段），此时状态不变。
func finish_round(result: Dictionary) -> bool:
	if _match_over:
		return false
	if not result.has_all(["dealer_side", "dealer_level", "catcher_level", "dealer_seat",
			"match_over", "match_winner", "next_dealer_side", "next_tribute"]):
		return false
	var dealer_side: int = result["dealer_side"]
	if dealer_side < 0 or dealer_side > 1:
		return false
	_levels[dealer_side] = result["dealer_level"]
	_levels[1 - dealer_side] = result["catcher_level"]
	_dealer_seat = result["dealer_seat"]
	_round_count += 1
	if result["match_over"]:
		_match_over = true
		# Settlement.Winner 是相对本局的庄/抓，此处换算为绝对 side
		match result["match_winner"]:
			Settlement.Winner.DEALER_SIDE:
				_winner = dealer_side
			Settlement.Winner.CATCHER_SIDE:
				_winner = 1 - dealer_side
	else:
		_dealer_side = result["next_dealer_side"]
		_next_tribute = (result["next_tribute"] as Dictionary).duplicate()
	return true


## 序列化为 JSON 兼容 Dictionary（供 user://match_save.json，只存局间状态）。字段：
## - version: 存档格式版本
## - base_seed: 洗牌种子基数，第 n 局（0 起）用 base_seed + n
## - round_count: 已完成局数
## - levels: [side0 级别, side1 级别]（side 0 = 座位 {0,2}，side 1 = 座位 {1,3}）
## - dealer_side: 下局庄家方（0/1）；SIDE_NONE(-1) = 首局未定（抢亮大王决定）
## - dealer_seat: 上一局庄家座位；-1 = 尚无已完成局（仅展示用，不影响流程）
## - next_tribute: 下局进贡参数 {score, bonus_big, bonus_small, bonus_active}，含义见 get_next_tribute
## - match_over / winner: 比赛结束标记与胜方（SIDE_NONE(-1) = 无；0/1 为 side）
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"base_seed": _base_seed,
		"round_count": _round_count,
		"levels": [_levels[0], _levels[1]],
		"dealer_side": _dealer_side,
		"dealer_seat": _dealer_seat,
		"next_tribute": _next_tribute.duplicate(),
		"match_over": _match_over,
		"winner": _winner,
	}


## 从 to_dict() 产出的 Dictionary 恢复比赛状态（兼容 JSON 反序列化后的 float 数值）。
static func from_dict(d: Dictionary) -> MatchState:
	var ms := MatchState.new(int(d.get("base_seed", 1)))
	var levels: Array = d.get("levels", [FIRST_LEVEL, FIRST_LEVEL])
	ms._levels[0] = int(levels[0])
	ms._levels[1] = int(levels[1])
	ms._round_count = int(d.get("round_count", 0))
	ms._dealer_side = int(d.get("dealer_side", SIDE_NONE))
	ms._dealer_seat = int(d.get("dealer_seat", -1))
	var tribute: Dictionary = d.get("next_tribute", {})
	ms._next_tribute = {
		"score": int(tribute.get("score", 0)),
		"bonus_big": int(tribute.get("bonus_big", 0)),
		"bonus_small": int(tribute.get("bonus_small", 0)),
		"bonus_active": bool(tribute.get("bonus_active", false)),
	}
	ms._match_over = bool(d.get("match_over", false))
	ms._winner = int(d.get("winner", SIDE_NONE))
	return ms
