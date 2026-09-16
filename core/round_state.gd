class_name RoundState
extends RefCounted
## 一局流程状态机（规则 §4~§8）：DEALING → BIDDING → TRIBUTE → BOTTOM → PLAYING → SETTLEMENT。
## 首局跳过 BIDDING 与 TRIBUTE（§4.2 抢亮大王/翻底牌定庄定主，§5 首局不进贡）。
## UI 与 AI 只能通过 get_available_actions / apply_action / close_bidding 驱动。
##
## 构造 config（Dictionary）键：
## - is_first_round: bool（默认 false）
## - dealer_side: int（0={0,2}，1={1,3}；首局忽略，由抢亮/翻底牌确定）
## - dealer_level / catcher_level: int（默认 3；级牌 = 庄家方当前级别，规则 §2）
## - tribute_score: int（上局抓分方总分 S，首局忽略）
## - tribute_bonus_big / tribute_bonus_small: int（上局底牌大/小王数，王奖励）
## - tribute_bonus_active: bool（王奖励是否生效，见规则 §8；干锅/分支5 传 false）
## - first_lead_seat: int（默认 -1 = 庄家领出第一轮，规则 §10）
## - seed: int（洗牌与兜底随机数种子，默认 1）
## - deck: Array[Card]（可选，测试用预排牌，须为 162 张，绕过洗牌）
##
## action（Dictionary，type 为 ActionType）格式：
## - DEAL {}：DEALING 阶段发一张牌（seat 忽略，UI 按动画节奏驱动）
## - BID {"kind","suit"}：亮/反主；王亮须指定主花色
## - TRIBUTE {"cards"}：进贡；首张贡手可贡 0 张，末位贡手须恰好补足剩余数
## - RETURN {"to_seat","cards"}：庄家按各自贡数分别还贡（非分副牌）
## - DISCARD_BOTTOM {"cards"×6}：庄家扣底（含扣王，有大王须先扣大王）
## - DISCARD_JOKERS {"cards"}：其他三家扣王；PASS {} 放弃扣王
## - PICK_COMPENSATION {"cards"}：扣王后从底牌捡等量最小非分牌
## - PLAY {"cards"}：领出（1~3 张合法牌型）或跟牌（张数同首家）

enum Phase { DEALING, BIDDING, TRIBUTE, BOTTOM, PLAYING, SETTLEMENT }
enum ActionType { DEAL, BID, TRIBUTE, RETURN, DISCARD_BOTTOM, DISCARD_JOKERS, PICK_COMPENSATION, PASS, PLAY }

const PLAYER_COUNT := 4
const DEAL_CARDS := 156  # 39 × 4
const FIRST_ROUND_LEVEL := 3

var _phase: int = Phase.DEALING
var _is_first_round: bool
var _dealer_side: int
var _dealer_seat: int = -1
var _dealer_level: int
var _catcher_level: int
var _level: int
var _trump_suit: int = Bidding.SUIT_UNDECIDED
var _tribute_score: int
var _tribute_bonus_big: int
var _tribute_bonus_small: int
var _tribute_bonus_active: bool
var _first_lead_seat: int
var _rng := RandomNumberGenerator.new()

var _deck: Array[Card] = []
var _deal_index: int = 0
var _hands: Array = []  # 4 × Array[Card]，发牌顺序即摸牌顺序
var _bottom: Array[Card] = []
var _bottom_public := false
var _dry_pot := false

var _current_bid: Bidding.Bid = null
var _current_bidder: int = -1
var _first_round_bidder: int = -1

var _tribute_payers: Array[int] = []
var _tribute_target := 0
var _tribute_given: Dictionary = {}  # seat -> 已贡张数
var _tribute_payer_idx := 0
var _returns_pending: Array[int] = []  # 尚待还贡的座位

var _dealer_discarded := false
var _bottom_queue: Array[int] = []  # 尚未决定扣王的座位
var _bottom_actor := -1
var _compensation_count := 0  # >0 表示 _bottom_actor 须先捡补偿牌

var _trick: Trick = null
var _lead_cards: Array[Card] = []
var _table_plays: Array = []  # 本轮已出：{"seat","cards"}
var _current_seat := -1
var _last_trick_winner := -1
var _side_scores: Array[int] = [0, 0]
var _result: Dictionary = {}


func _init(config: Dictionary) -> void:
	_is_first_round = config.get("is_first_round", false)
	_dealer_side = config.get("dealer_side", 0)
	_dealer_level = config.get("dealer_level", FIRST_ROUND_LEVEL)
	_catcher_level = config.get("catcher_level", FIRST_ROUND_LEVEL)
	_tribute_score = config.get("tribute_score", 0)
	_tribute_bonus_big = config.get("tribute_bonus_big", 0)
	_tribute_bonus_small = config.get("tribute_bonus_small", 0)
	_tribute_bonus_active = config.get("tribute_bonus_active", false)
	_first_lead_seat = config.get("first_lead_seat", -1)
	var seed: int = config.get("seed", 1)
	_rng.seed = seed + 999
	if config.has("deck"):
		_deck.assign(config["deck"])
	else:
		_deck = Deck.shuffled(seed)
	_bottom.assign(_deck.slice(DEAL_CARDS))
	for i in PLAYER_COUNT:
		var hand: Array[Card] = []
		_hands.append(hand)
	if _is_first_round:
		_dealer_level = FIRST_ROUND_LEVEL
		_catcher_level = FIRST_ROUND_LEVEL
	_level = _dealer_level


## 座位所属方：{0,2}=0，{1,3}=1（规则 §1）。
static func side_of(seat: int) -> int:
	return seat % 2


## 一方的两个座位，座号升序。
static func side_seats(side: int) -> Array[int]:
	var seats: Array[int] = []
	seats.assign([0, 2] if side == 0 else [1, 3])
	return seats


## 当前阶段指定座位可执行的动作列表（动作格式见类 docstring）。
func get_available_actions(seat: int) -> Array:
	if seat < 0 or seat >= PLAYER_COUNT:
		return []
	match _phase:
		Phase.DEALING:
			return [{"type": ActionType.DEAL}] + _bid_actions(seat)
		Phase.BIDDING:
			return _bid_actions(seat)
		Phase.TRIBUTE:
			return _tribute_actions(seat)
		Phase.BOTTOM:
			return _bottom_actions(seat)
		Phase.PLAYING:
			return _play_actions(seat)
	return []


## 执行动作并推进状态；非法动作返回 false 且状态不变。
func apply_action(seat: int, action: Dictionary) -> bool:
	if seat < 0 or seat >= PLAYER_COUNT:
		return false
	var action_type: int = action.get("type", -1)
	match action_type:
		ActionType.DEAL:
			return _apply_deal()
		ActionType.BID:
			return _apply_bid(seat, action)
		ActionType.TRIBUTE:
			return _apply_tribute(seat, action)
		ActionType.RETURN:
			return _apply_return(seat, action)
		ActionType.DISCARD_BOTTOM:
			return _apply_discard_bottom(seat, action)
		ActionType.DISCARD_JOKERS:
			return _apply_discard_jokers(seat, action)
		ActionType.PICK_COMPENSATION:
			return _apply_pick_compensation(seat, action)
		ActionType.PASS:
			return _apply_pass(seat, action)
		ActionType.PLAY:
			return _apply_play(seat, action)
	return false


## 关闭亮主倒计时窗口（时间由 UI 控制，规则 §4.3）；仅 BIDDING 阶段有效。
func close_bidding() -> bool:
	if _phase != Phase.BIDDING:
		return false
	if _current_bid == null:
		# 规则 §4.3：无人亮主，从底牌随机抽一张（抽到王继续抽）定主
		var suited: Array[Card] = []
		for card in _bottom:
			if not card.is_joker():
				suited.append(card)
		if suited.is_empty():
			_trump_suit = _rng.randi_range(0, 3)  # 底牌全王的极端情形，规则未定义，兜底随机
		else:
			_trump_suit = suited[_rng.randi_range(0, suited.size() - 1)].suit
	else:
		_trump_suit = _current_bid.suit
	_decide_dealer()
	_enter_tribute()
	return true


func get_phase() -> int:
	return _phase


## 指定座位的手牌（含进贡/扣底/扣王变动后的实时内容）。
func get_hand(seat: int) -> Array[Card]:
	return _hands[seat].duplicate()


## 本轮桌面已出的牌：[{"seat","cards"}]，按出牌顺序。
func get_table_plays() -> Array:
	return _table_plays.duplicate()


## 一方已累计的桌面分（不含底牌分）。
func get_side_score(side: int) -> int:
	return _side_scores[side]


func get_bottom() -> Array[Card]:
	return _bottom.duplicate()


func get_trump_suit() -> int:
	return _trump_suit


func get_level() -> int:
	return _level


func get_dealer_seat() -> int:
	return _dealer_seat


func get_dealer_side() -> int:
	return _dealer_side


## PLAYING 阶段当前应出牌的座位，其他阶段为 -1。
func get_current_seat() -> int:
	return _current_seat


## 当前最高叫价；无人叫价为 null。
func get_current_bid() -> Bidding.Bid:
	return _current_bid


## 底牌是否已公开（扣了王则必须亮明，规则 §6）。
func is_bottom_public() -> bool:
	return _bottom_public


## 是否干锅（规则 §6.4）。
func is_dry_pot() -> bool:
	return _dry_pot


## 一局结果（SETTLEMENT 阶段后有效）：settlement 结果 + next_dealer_side /
## next_tribute（下局进贡参数）/ catcher_score / kongdi / dry_pot / bottom_score /
## in_play_scores / dealer_seat / dealer_side / trump_suit / level。
func get_result() -> Dictionary:
	return _result


func _apply_deal() -> bool:
	if _phase != Phase.DEALING:
		return false
	_hands[_deal_index % PLAYER_COUNT].append(_deck[_deal_index])
	_deal_index += 1
	if _deal_index == DEAL_CARDS:
		_finish_dealing()
	return true


func _finish_dealing() -> void:
	if _is_first_round:
		_finalize_first_round()
		_enter_bottom()
	else:
		_phase = Phase.BIDDING


# 规则 §4.2：抢亮大王者坐庄（不可被反），以之后摸到的第一张花色牌定主；
# 无人亮大王则翻底牌比大小定庄，同点数先翻者为庄。
func _finalize_first_round() -> void:
	if _first_round_bidder >= 0:
		_dealer_seat = _first_round_bidder
		var hand: Array[Card] = _hands[_dealer_seat]
		var joker_idx := -1
		for i in hand.size():
			if hand[i].is_big_joker():
				joker_idx = i
				break
		_trump_suit = Bidding.first_round_trump_suit(hand.slice(joker_idx + 1))
	else:
		var best_seat := 0
		for seat in range(1, PLAYER_COUNT):
			if _bottom[seat].rank > _bottom[best_seat].rank:
				best_seat = seat
		_dealer_seat = best_seat
		_trump_suit = _bottom[best_seat].suit
		if _trump_suit == Card.Suit.NONE:
			_trump_suit = _first_suited_in_bottom()  # 翻到大王，规则未定义，取底牌首张花色牌
	if _trump_suit == Bidding.SUIT_UNDECIDED or _trump_suit == Card.Suit.NONE:
		_trump_suit = _rng.randi_range(0, 3)  # 极端情形兜底随机花色
	_dealer_side = side_of(_dealer_seat)


func _apply_bid(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.DEALING and _phase != Phase.BIDDING:
		return false
	var kind: int = action.get("kind", Bidding.Kind.NONE)
	var suit: int = action.get("suit", Bidding.SUIT_UNDECIDED)
	for available in _bid_actions(seat):
		if available.kind == kind and available.suit == suit:
			_current_bid = Bidding.Bid.new(kind, suit)
			_current_bidder = seat
			if _is_first_round:
				_first_round_bidder = seat
			return true
	return false


# 规则 §10：庄家方成员是最终亮主/反主成功者则由其坐庄；
# 否则庄家方两人中主牌张数多者坐庄，并列时座号较小者。
func _decide_dealer() -> void:
	if _current_bidder >= 0 and side_of(_current_bidder) == _dealer_side:
		_dealer_seat = _current_bidder
		return
	var mates := side_seats(_dealer_side)
	if _count_trumps(mates[0]) >= _count_trumps(mates[1]):
		_dealer_seat = mates[0]
	else:
		_dealer_seat = mates[1]


# 规则 §5：进贡方 = 本局抓分方（非庄家方），收贡人始终是本局庄家。
func _enter_tribute() -> void:
	_tribute_target = Tribute.total_count(
		_tribute_score, _tribute_bonus_big, _tribute_bonus_small, _tribute_bonus_active)
	_tribute_payers = side_seats(1 - _dealer_side)
	_tribute_given.clear()
	_tribute_payer_idx = 0
	_returns_pending.clear()
	_phase = Phase.TRIBUTE


func _apply_tribute(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.TRIBUTE or not _returns_pending.is_empty():
		return false
	if seat != _tribute_payers[_tribute_payer_idx]:
		return false
	var cards := _typed_cards(action.get("cards", []))
	var remaining := _tribute_target - _given_total()
	var is_last := _tribute_payer_idx == _tribute_payers.size() - 1
	if is_last:
		if cards.size() != remaining:
			return false
	elif cards.size() > remaining:
		return false
	if not cards.is_empty():
		if not _cards_in_hand(_hands[seat], cards):
			return false
		if not Tribute.can_tribute(_hands[seat], cards, _level, _trump_suit):
			return false
	_move_cards(_hands[seat], _hands[_dealer_seat], cards)
	_tribute_given[seat] = cards.size()
	_tribute_payer_idx += 1
	if _tribute_payer_idx == _tribute_payers.size():
		for payer in _tribute_payers:
			if _tribute_given.get(payer, 0) > 0:
				_returns_pending.append(payer)
	return true


func _apply_return(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.TRIBUTE or _returns_pending.is_empty():
		return false
	if seat != _dealer_seat:
		return false
	var to_seat: int = action.get("to_seat", -1)
	if not _returns_pending.has(to_seat):
		return false
	var cards := _typed_cards(action.get("cards", []))
	if cards.size() != _tribute_given[to_seat]:
		return false
	if not _cards_in_hand(_hands[seat], cards):
		return false
	if not Tribute.can_return(cards, _level, _trump_suit):
		return false
	_move_cards(_hands[seat], _hands[to_seat], cards)
	_returns_pending.erase(to_seat)
	if _returns_pending.is_empty():
		_enter_bottom()
	return true


func _enter_bottom() -> void:
	_hands[_dealer_seat].append_array(_bottom)
	_bottom.clear()
	_dealer_discarded = false
	_bottom_queue.clear()
	_bottom_actor = -1
	_compensation_count = 0
	_phase = Phase.BOTTOM


# 规则 §6.1/§6.2：庄家取走底牌后扣回 6 张（含扣王，有大王须先扣大王）；
# 扣了王则底牌亮明；亮明后全主或全副判干锅，底牌冻结（§6.4）。
func _apply_discard_bottom(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.BOTTOM or _dealer_discarded:
		return false
	if seat != _dealer_seat:
		return false
	var cards := _typed_cards(action.get("cards", []))
	if cards.size() != Deck.BOTTOM_SIZE:
		return false
	var hand: Array[Card] = _hands[seat]
	if not _cards_in_hand(hand, cards):
		return false
	var jokers: Array[Card] = []
	for card in cards:
		if card.is_joker():
			jokers.append(card)
	if not jokers.is_empty() and not Bottom.can_discard_jokers(hand, jokers):
		return false
	_remove_cards(hand, cards)
	_bottom = cards
	_dealer_discarded = true
	_bottom_public = not jokers.is_empty()
	if _bottom_public and Bottom.is_dry_pot(_bottom, _level, _trump_suit):
		_dry_pot = true
		_enter_playing()
		return true
	for i in range(1, PLAYER_COUNT):
		_bottom_queue.append((_dealer_seat + i) % PLAYER_COUNT)
	_advance_bottom_queue()
	return true


# 规则 §6.3：其他三家也可扣王（底牌随之公开），随后须捡等量最小非分牌作补偿。
func _apply_discard_jokers(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.BOTTOM or not _dealer_discarded or _compensation_count > 0:
		return false
	if _bottom_queue.is_empty() or seat != _bottom_actor:
		return false
	var cards := _typed_cards(action.get("cards", []))
	if not Bottom.can_discard_jokers(_hands[seat], cards):
		return false
	_move_cards(_hands[seat], _bottom, cards)
	_bottom_public = true
	_compensation_count = cards.size()
	return true


func _apply_pick_compensation(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.BOTTOM or _compensation_count == 0 or seat != _bottom_actor:
		return false
	var cards := _typed_cards(action.get("cards", []))
	if cards.size() != _compensation_count:
		return false
	if not Bottom.can_pick_compensation(_bottom, cards, _level, _trump_suit):
		return false
	_move_cards(_bottom, _hands[seat], cards)
	_compensation_count = 0
	_bottom_queue.pop_front()
	if Bottom.is_dry_pot(_bottom, _level, _trump_suit):
		# 规则 §6.4：公开底牌全主或全副，后续不能再扣王
		_dry_pot = true
		_bottom_queue.clear()
	_advance_bottom_queue()
	return true


func _apply_pass(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.BOTTOM or not _dealer_discarded or _compensation_count > 0:
		return false
	if _bottom_queue.is_empty() or seat != _bottom_actor:
		return false
	_bottom_queue.pop_front()
	_advance_bottom_queue()
	return true


func _advance_bottom_queue() -> void:
	if _bottom_queue.is_empty():
		_enter_playing()
	else:
		_bottom_actor = _bottom_queue[0]


func _enter_playing() -> void:
	_phase = Phase.PLAYING
	_start_trick(_dealer_seat if _first_lead_seat < 0 else _first_lead_seat)


func _start_trick(leader: int) -> void:
	_trick = Trick.new(leader, _level, _trump_suit)
	_lead_cards = []
	_table_plays = []
	_current_seat = leader


func _apply_play(seat: int, action: Dictionary) -> bool:
	if _phase != Phase.PLAYING or seat != _current_seat:
		return false
	var cards := _typed_cards(action.get("cards", []))
	var hand: Array[Card] = _hands[seat]
	if cards.is_empty() or not _cards_in_hand(hand, cards):
		return false
	if _lead_cards.is_empty():
		if Play.identify(cards) == Play.Type.INVALID:
			return false
	elif not Trick.can_follow(hand, _lead_cards, cards, _level, _trump_suit):
		return false
	_remove_cards(hand, cards)
	if _lead_cards.is_empty():
		_lead_cards = cards
	_trick.add_play(seat, cards)
	_table_plays.append({"seat": seat, "cards": cards})
	if _trick.is_complete():
		var winner := _trick.winner_seat()
		_side_scores[side_of(winner)] += _trick.score()
		_last_trick_winner = winner
		if _hands[0].is_empty():
			_settle()
		else:
			_start_trick(winner)
	else:
		_current_seat = (_current_seat + 1) % PLAYER_COUNT
	return true


# 规则 §8：抠底 = 最后一轮抓分方赢，底牌分翻 2 倍计入 S；保底按面值归庄家方。
func _settle() -> void:
	var catcher_side := 1 - _dealer_side
	var kongdi := side_of(_last_trick_winner) == catcher_side
	var bottom_score := 0
	var big_jokers := 0
	var small_jokers := 0
	for card in _bottom:
		bottom_score += card.score_value()
		if card.is_big_joker():
			big_jokers += 1
		elif card.is_small_joker():
			small_jokers += 1
	var s: int = _side_scores[catcher_side] + (2 * bottom_score if kongdi else 0)
	_result = Settlement.settle(s, kongdi, big_jokers, small_jokers, _dry_pot, _dealer_level, _catcher_level)
	_result["catcher_score"] = s
	_result["kongdi"] = kongdi
	_result["dry_pot"] = _dry_pot
	_result["bottom_score"] = bottom_score
	_result["in_play_scores"] = [_side_scores[0], _side_scores[1]]
	_result["next_dealer_side"] = catcher_side if _result["catcher_on_stage"] else _dealer_side
	_result["next_tribute"] = {
		"score": s,
		"bonus_big": big_jokers,
		"bonus_small": small_jokers,
		"bonus_active": not _dry_pot and _result["branch"] != 5 and not _result["match_over"],
	}
	_result["dealer_seat"] = _dealer_seat
	_result["dealer_side"] = _dealer_side
	_result["trump_suit"] = _trump_suit
	_result["level"] = _level
	_phase = Phase.SETTLEMENT


func _bid_actions(seat: int) -> Array:
	var actions: Array = []
	for bid in Bidding.legal_bids(_hands[seat], _level, _current_bid, _is_first_round):
		if bid.kind == Bidding.Kind.SMALL_JOKERS_3 or bid.kind == Bidding.Kind.BIG_JOKERS_3:
			# 规则 §4.3：王亮可指定任意花色为主，展开为 4 个具体叫价
			for suit in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]:
				actions.append({"type": ActionType.BID, "kind": bid.kind, "suit": suit})
		else:
			actions.append({"type": ActionType.BID, "kind": bid.kind, "suit": bid.suit})
	return actions


func _tribute_actions(seat: int) -> Array:
	if not _returns_pending.is_empty():
		if seat != _dealer_seat:
			return []
		var actions: Array = []
		for owed in _returns_pending:
			actions.append({"type": ActionType.RETURN, "to_seat": owed, "count": _tribute_given[owed]})
		return actions
	if seat != _tribute_payers[_tribute_payer_idx]:
		return []
	var remaining := _tribute_target - _given_total()
	var is_last := _tribute_payer_idx == _tribute_payers.size() - 1
	var min_count := remaining if is_last else 0
	return [{"type": ActionType.TRIBUTE, "min_count": min_count, "max_count": remaining}]


func _bottom_actions(seat: int) -> Array:
	if not _dealer_discarded:
		if seat == _dealer_seat:
			return [{"type": ActionType.DISCARD_BOTTOM, "count": Deck.BOTTOM_SIZE}]
		return []
	if _compensation_count > 0:
		if seat == _bottom_actor:
			return [{"type": ActionType.PICK_COMPENSATION, "count": _compensation_count}]
		return []
	if not _bottom_queue.is_empty() and seat == _bottom_actor:
		var actions: Array = [{"type": ActionType.PASS}]
		for card in _hands[seat]:
			if card.is_joker():
				actions.push_front({"type": ActionType.DISCARD_JOKERS})
				break
		return actions
	return []


func _play_actions(seat: int) -> Array:
	if seat != _current_seat:
		return []
	if not _lead_cards.is_empty():
		return [{"type": ActionType.PLAY, "count": _lead_cards.size()}]
	var actions: Array = []
	for count in [1, 2, 3]:
		actions.append({"type": ActionType.PLAY, "count": count})
	return actions


func _given_total() -> int:
	var total := 0
	for count in _tribute_given.values():
		total += count
	return total


func _count_trumps(seat: int) -> int:
	var count := 0
	for card in _hands[seat]:
		if Play.is_trump(card, _level, _trump_suit):
			count += 1
	return count


func _first_suited_in_bottom() -> int:
	for card in _bottom:
		if not card.is_joker():
			return card.suit
	return Bidding.SUIT_UNDECIDED


static func _typed_cards(value: Variant) -> Array[Card]:
	var cards: Array[Card] = []
	if value is Array:
		cards.assign(value)
	return cards


static func _index_identical(hand: Array[Card], card: Card) -> int:
	for i in hand.size():
		if hand[i].is_identical(card):
			return i
	return -1


static func _cards_in_hand(hand: Array[Card], cards: Array[Card]) -> bool:
	var pool: Array[Card] = hand.duplicate()
	for card in cards:
		var idx := _index_identical(pool, card)
		if idx == -1:
			return false
		pool.remove_at(idx)
	return true


static func _remove_cards(hand: Array[Card], cards: Array[Card]) -> void:
	for card in cards:
		hand.remove_at(_index_identical(hand, card))


static func _move_cards(from: Array[Card], to: Array[Card], cards: Array[Card]) -> void:
	_remove_cards(from, cards)
	to.append_array(cards)
