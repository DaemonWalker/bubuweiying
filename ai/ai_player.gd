class_name AIPlayer
extends RefCounted
## AI 接口（抽象基类）：方法与 RoundState 的动作一一对应（architecture.md §AI）。
## 所有 decide_* 返回具体化的 action Dictionary，可直接交给 RoundState.apply_action；
## 返回空 Dictionary 表示不行动（放弃叫价等允许不行动的场合）。
## 基类实现一律"不行动"，只能驱动允许跳过的场合；decide_tribute_give /
## decide_tribute_return / decide_bottom / decide_play 等必须行动的场合子类必须重写。

## 新一局开始：清空记牌。级牌此时已知（= 庄家方级别），主花色在亮主后才有。
func start_round(_round_state: RoundState, _seat: int) -> void:
	pass


## 每手出牌成功后由驱动方通知（含自己出的牌），用于记牌。
func observe_play(_seat: int, _cards: Array[Card]) -> void:
	pass


## 亮主/反主（DEALING / BIDDING 阶段，规则 §4）。返回 BID action 或 {} 不叫。
func decide_bid(_round_state: RoundState, _seat: int) -> Dictionary:
	return {}


## 进贡（规则 §5）：按 get_available_actions 的 min_count/max_count 描述符返回 TRIBUTE action。
func decide_tribute_give(_round_state: RoundState, _seat: int) -> Dictionary:
	return {}


## 还贡（规则 §5，庄家）：按描述符返回 RETURN action（to_seat + cards）。
func decide_tribute_return(_round_state: RoundState, _seat: int) -> Dictionary:
	return {}


## 庄家扣底（规则 §6.1/§6.2）：返回 DISCARD_BOTTOM action（6 张，含扣王则先大王后小王）。
func decide_bottom(_round_state: RoundState, _seat: int) -> Dictionary:
	return {}


## 其他三家扣王 / 捡补偿（规则 §6.3）：返回 DISCARD_JOKERS / PICK_COMPENSATION / PASS。
func decide_bottom_joker(_round_state: RoundState, _seat: int) -> Dictionary:
	return {"type": RoundState.ActionType.PASS}


## 出牌（规则 §7）：首家领出（1~3 张合法牌型）或跟牌（张数同首家），返回 PLAY action。
func decide_play(_round_state: RoundState, _seat: int) -> Dictionary:
	return {}
