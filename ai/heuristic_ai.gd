class_name HeuristicAI
extends AIPlayer
## 启发式 AI：逐张记牌（已出副本计数，王/级牌/分牌由此推导）+ 阈值策略。
## - 亮主/反主：按拟任主花色下的主牌长度阈值（规则 §4）；3 王亮必叫并选最强花色。
## - 进贡：贡手中最大的非分牌；多张时首贡手贡一半（向下取整）、末位补足（§5 约定分摊）。
## - 还贡：最小的非分副牌（§5）。
## - 扣底：优先非分副牌；主牌够强时扣王赌保底（§6.2 先大王后小王），留副牌防干锅（§6.4）。
## - 其他家扣王：庄家方加码已亮底的底牌；抓分方主牌够强时扣王赌抠底（§8 分支4/分支3）。
## - 出牌：领出优先"无人能压"的滚子/棒子（记牌判定），否则非分小牌单张试探；
##   跟牌能赢则最小代价赢，队友已赢则喂分，赢不了垫最小非分牌（§7）；
##   末轮（手牌 ≤3）出最大牌型抢抠底/保底（§8）。

const BID_LEVEL_1_MIN := 16  # 亮 1 张级牌所需拟任主花色下的主牌张数
const BID_LEVEL_2_MIN := 15
const BID_LEVEL_3_MIN := 14
const REBID_EXTRA := 1  # 反主（已有人叫价）时的阈值加成
const BOTTOM_JOKER_TRUMP_MIN := 20  # 庄家扣王赌保底所需的主牌张数（45 张中）
const CATCHER_JOKER_TRUMP_MIN := 18  # 抓分方扣王赌抠底所需的主牌张数（39 张中）
const LAST_TRICK_HAND := 3  # 手牌 ≤ 3 即最后一轮
const DECK_COPIES := 3  # 每种牌 3 个副本（3 副牌）

var _level := 3
var _played := {}  # "suit:rank" -> 已打出副本数
var _threats: Array = []  # 全牌表缓存：{"suit","rank","power","trump"}，按 level+trump 记忆
var _threats_key := ""


func start_round(round_state: RoundState, _seat: int) -> void:
	_level = round_state.get_level()
	_played.clear()
	_threats_key = ""


func observe_play(_seat: int, cards: Array[Card]) -> void:
	for card in cards:
		var key := _key_of(card)
		_played[key] = _played.get(key, 0) + 1


func decide_bid(round_state: RoundState, seat: int) -> Dictionary:
	var bids: Array = []
	for action in round_state.get_available_actions(seat):
		if action.get("type") == RoundState.ActionType.BID:
			bids.append(action)
	if bids.is_empty():
		return {}
	for action in bids:
		if action.get("kind") == Bidding.Kind.FIRST_ROUND_JOKER:
			return action  # 规则 §4.2：抢亮大王必抢（坐庄且不可被反）
	var hand := round_state.get_hand(seat)
	var extra := REBID_EXTRA if round_state.get_current_bid() != null else 0
	for kind in [Bidding.Kind.BIG_JOKERS_3, Bidding.Kind.SMALL_JOKERS_3,
			Bidding.Kind.LEVEL_3, Bidding.Kind.LEVEL_2, Bidding.Kind.LEVEL_1]:
		var best_action := {}
		var best_strength := -1
		for action in bids:
			if action.get("kind") != kind:
				continue
			var strength := _trump_count_if(hand, action.get("suit"))
			if strength > best_strength:
				best_strength = strength
				best_action = action
		if best_strength >= _bid_threshold(kind) + extra:
			return best_action
	return {}


func decide_tribute_give(round_state: RoundState, seat: int) -> Dictionary:
	var desc := _first_action(round_state, seat, RoundState.ActionType.TRIBUTE)
	var remaining: int = desc.get("max_count", 0)
	var min_count: int = desc.get("min_count", 0)
	# 规则 §5 分摊约定：首贡手贡一半（向下取整），末位贡手补足（奇数由末位多贡）
	var count := min_count if min_count > 0 else remaining / 2
	var cards := _top_non_score(round_state.get_hand(seat),
		round_state.get_level(), round_state.get_trump_suit(), count)
	return {"type": RoundState.ActionType.TRIBUTE, "cards": cards}


func decide_tribute_return(round_state: RoundState, seat: int) -> Dictionary:
	var desc := _first_action(round_state, seat, RoundState.ActionType.RETURN)
	var level := round_state.get_level()
	var trump := round_state.get_trump_suit()
	var candidates: Array[Card] = []
	for card in round_state.get_hand(seat):
		if card.score_value() == 0 and not Play.is_trump(card, level, trump):
			candidates.append(card)  # 规则 §5：还贡必须是非分副牌
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) < Play.power(b, level, trump))
	var count: int = desc.get("count", 0)
	return {"type": RoundState.ActionType.RETURN, "to_seat": desc.get("to_seat", -1),
		"cards": candidates.slice(0, count)}


func decide_bottom(round_state: RoundState, seat: int) -> Dictionary:
	var hand := round_state.get_hand(seat)
	var level := round_state.get_level()
	var trump := round_state.get_trump_suit()
	var bigs: Array[Card] = []
	var smalls: Array[Card] = []
	var trump_count := 0
	for card in hand:
		if card.is_big_joker():
			bigs.append(card)
		elif card.is_small_joker():
			smalls.append(card)
		if Play.is_trump(card, level, trump):
			trump_count += 1
	var jokers: Array[Card] = []
	# 规则 §8 分支7 王追加升级：主牌够强时扣王赌保底；§6.2 有大王须先扣大王
	if not bigs.is_empty() and trump_count >= BOTTOM_JOKER_TRUMP_MIN:
		jokers.append_array(bigs)
		jokers.append_array(smalls)
		if jokers.size() >= Deck.BOTTOM_SIZE:
			jokers = jokers.slice(0, Deck.BOTTOM_SIZE - 1)  # §6.4 留至少 1 个副牌位防全主干锅
	var picked: Array[Card] = []
	picked.append_array(jokers)
	var rest := hand.duplicate()
	for card in jokers:
		_remove_identical(rest, card)
	rest.sort_custom(func(a: Card, b: Card) -> bool:
		return _discard_key(a, level, trump) < _discard_key(b, level, trump))
	while picked.size() < Deck.BOTTOM_SIZE:
		picked.append(rest[0])
		rest.remove_at(0)
	if not jokers.is_empty() and Bottom.is_dry_pot(picked, level, trump):
		# 干锅兜底（极端手牌）：放弃扣王，改扣最小的 6 张非王牌
		picked = []
		for card in rest:
			if not card.is_joker():
				picked.append(card)
				if picked.size() == Deck.BOTTOM_SIZE:
					break
	return {"type": RoundState.ActionType.DISCARD_BOTTOM, "cards": picked}


func decide_bottom_joker(round_state: RoundState, seat: int) -> Dictionary:
	var level := round_state.get_level()
	var trump := round_state.get_trump_suit()
	var comp := _first_action(round_state, seat, RoundState.ActionType.PICK_COMPENSATION)
	if not comp.is_empty():
		# 规则 §6.3：扣王后从底牌捡等量的最小非分牌
		var candidates: Array[Card] = []
		for card in round_state.get_bottom():
			if card.score_value() == 0:
				candidates.append(card)
		candidates.sort_custom(func(a: Card, b: Card) -> bool:
			return Play.power(a, level, trump) < Play.power(b, level, trump))
		var count: int = comp.get("count", 0)
		return {"type": RoundState.ActionType.PICK_COMPENSATION, "cards": candidates.slice(0, count)}
	# 规则 §6.3：庄家方仅在底牌已公开（庄家已扣王）时追加扣王加码王奖励；
	# 抓分方主牌够强时也扣全部王，赌 §8 分支4 王追加升级与分支3 的 3 大王特殊结束
	var is_dealer_side := RoundState.side_of(seat) == round_state.get_dealer_side()
	if is_dealer_side and not round_state.is_bottom_public():
		return {"type": RoundState.ActionType.PASS}
	var discarding: Array[Card] = []
	var trump_count := 0
	for card in round_state.get_hand(seat):
		if card.is_joker():
			discarding.append(card)  # 全部扣入，大王全在其中必满足 §6.2 先大王后小王
		if Play.is_trump(card, level, trump):
			trump_count += 1
	if discarding.is_empty():
		return {"type": RoundState.ActionType.PASS}
	if not is_dealer_side and trump_count < CATCHER_JOKER_TRUMP_MIN:
		return {"type": RoundState.ActionType.PASS}  # 手牌不强不赌：扣王会削弱牌力且可能资敌（§8 分支7）
	var simulated := round_state.get_bottom()
	simulated.append_array(discarding)
	if Bottom.is_dry_pot(simulated, level, trump):
		return {"type": RoundState.ActionType.PASS}  # §6.4 干锅风险：扣王后全主/全副则放弃
	return {"type": RoundState.ActionType.DISCARD_JOKERS, "cards": discarding}


func decide_play(round_state: RoundState, seat: int) -> Dictionary:
	var hand := round_state.get_hand(seat)
	var level := round_state.get_level()
	var trump := round_state.get_trump_suit()
	var table := round_state.get_table_plays()
	var cards: Array[Card]
	if table.is_empty():
		cards = _lead(hand, level, trump)
	else:
		cards = _follow(hand, table, seat, level, trump)
	return {"type": RoundState.ActionType.PLAY, "cards": cards}


func _lead(hand: Array[Card], level: int, trump: int) -> Array[Card]:
	if hand.size() <= LAST_TRICK_HAND:
		return _strongest_combo(hand, level, trump)  # §8 末轮：最大牌型抢抠底/保底
	for size in [DECK_COPIES, 2]:
		var combo := _best_safe_combo(hand, size, level, trump)
		if not combo.is_empty():
			return combo
	return [_probe(hand, level, trump)]


# 试探领出：不拆对子的最小非分副牌 → 任意最小非分副牌 → 最小非分主牌 → 最小牌。
func _probe(hand: Array[Card], level: int, trump: int) -> Card:
	var counts := _group_by_card(hand)
	for pass_no in 4:
		var best: Card = null
		for card in hand:
			var non_score := card.score_value() == 0
			var side := not Play.is_trump(card, level, trump)
			var ok: bool
			match pass_no:
				0:
					ok = non_score and side and counts[_key_of(card)].size() == 1
				1:
					ok = non_score and side
				2:
					ok = non_score
				_:
					ok = true
			if ok and (best == null or Play.power(card, level, trump) < Play.power(best, level, trump)):
				best = card
		if best != null:
			return best
	return hand[0]


func _follow(hand: Array[Card], table: Array, seat: int, level: int, trump: int) -> Array[Card]:
	var lead: Array[Card] = table[0].cards
	var n := lead.size()
	var best_idx := 0
	for i in range(1, table.size()):
		if Play.beats(table[best_idx].cards, table[i].cards, level, trump):
			best_idx = i
	var winner: int = table[best_idx].seat
	var mate := (seat + 2) % RoundState.PLAYER_COUNT
	var lead_trump := Play.is_trump(lead[0], level, trump)
	var group: Array[Card] = []
	var rest: Array[Card] = []
	for card in hand:
		if _in_lead_group(card, lead_trump, lead[0].suit, level, trump):
			group.append(card)
		else:
			rest.append(card)
	if winner != mate and group.size() >= n:
		var win := _cheapest_winning(group, table[best_idx].cards, n, level, trump)
		if not win.is_empty():
			return win  # §7.3 能赢则以最小代价赢
	var chosen: Array[Card] = []
	var must := mini(group.size(), n)
	chosen.append_array(_select_follow(group, must, winner == mate, level, trump))
	chosen.append_array(_select_follow(rest, n - must, winner == mate, level, trump))
	return chosen


# 规则 §7.2 的跟牌分组（与 Trick._in_lead_group 同口径）：首家为主则主牌一组，
# 否则该花色副牌一组（级牌与 2 是主牌，不算该花色副牌）。
func _in_lead_group(card: Card, lead_trump: bool, lead_suit: int, level: int, trump: int) -> bool:
	if lead_trump:
		return Play.is_trump(card, level, trump)
	return card.suit == lead_suit and not Play.is_trump(card, level, trump)


# 同牌型且能压过当前最大的组合中牌力最小的一手；没有则返回空。
func _cheapest_winning(group: Array[Card], best_cards: Array[Card], n: int,
		level: int, trump: int) -> Array[Card]:
	var best: Array[Card] = []
	var groups := _group_by_card(group)
	for key in groups:
		var copies: Array[Card] = groups[key]
		if copies.size() < n:
			continue
		var combo: Array[Card] = copies.slice(0, n)
		if not Play.beats(best_cards, combo, level, trump):
			continue
		if best.is_empty() or Play.power(combo[0], level, trump) < Play.power(best[0], level, trump):
			best = combo
	return best


# 垫牌选 count 张：队友已赢则优先喂分（§7.3 赢家收走桌面分牌），否则垫最小的非分牌。
func _select_follow(cards: Array[Card], count: int, feed_score: bool, level: int, trump: int) -> Array[Card]:
	if count <= 0 or cards.is_empty():
		return []
	var sorted := cards.duplicate()
	if feed_score:
		sorted.sort_custom(func(a: Card, b: Card) -> bool:
			if a.score_value() != b.score_value():
				return a.score_value() > b.score_value()
			return Play.power(a, level, trump) > Play.power(b, level, trump))
	else:
		sorted.sort_custom(func(a: Card, b: Card) -> bool:
			if (a.score_value() == 0) != (b.score_value() == 0):
				return a.score_value() == 0
			return Play.power(a, level, trump) < Play.power(b, level, trump))
	return sorted.slice(0, count)


func _strongest_combo(hand: Array[Card], level: int, trump: int) -> Array[Card]:
	var groups := _group_by_card(hand)
	for size in [DECK_COPIES, 2]:
		var best: Array[Card] = []
		for key in groups:
			var copies: Array[Card] = groups[key]
			if copies.size() >= size and (best.is_empty() or
					Play.power(copies[0], level, trump) > Play.power(best[0], level, trump)):
				best = copies.slice(0, size)
		if not best.is_empty():
			return best
	var top := hand[0]
	for card in hand:
		if Play.power(card, level, trump) > Play.power(top, level, trump):
			top = card
	return [top]


# 最高牌力的"安全"滚子/棒子：记牌判定能压它的每种牌剩余副本都不足 size，无人能凑出（§7.3）。
func _best_safe_combo(hand: Array[Card], size: int, level: int, trump: int) -> Array[Card]:
	var best: Array[Card] = []
	var groups := _group_by_card(hand)
	for key in groups:
		var copies: Array[Card] = groups[key]
		if copies.size() < size:
			continue
		if _is_safe(copies[0], size, hand, level, trump):
			if best.is_empty() or Play.power(copies[0], level, trump) > Play.power(best[0], level, trump):
				best = copies.slice(0, size)
	return best


func _is_safe(card: Card, size: int, hand: Array[Card], level: int, trump: int) -> bool:
	var card_power := Play.power(card, level, trump)
	var card_trump := Play.is_trump(card, level, trump)
	for entry in _threat_table(level, trump):
		var suit: int = entry.suit
		var rank: int = entry.rank
		if suit == card.suit and rank == card.rank:
			continue
		var threatens: bool
		if card_trump:
			threatens = entry.trump and entry.power > card_power
		else:
			# 副牌牌型：同花色更大或任意主牌同牌型可压（§7.3 主杀副须同牌型）
			threatens = entry.trump or (suit == card.suit and entry.power > card_power)
		if not threatens:
			continue
		var unseen: int = DECK_COPIES - int(_played.get("%d:%d" % [suit, rank], 0)) \
			- _count_in_hand(hand, suit, rank)
		if unseen >= size:
			return false
	return true


func _threat_table(level: int, trump: int) -> Array:
	var key := "%d:%d" % [level, trump]
	if _threats_key == key:
		return _threats
	_threats_key = key
	_threats.clear()
	for suit in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]:
		for rank in range(2, 15):
			_add_threat(suit, rank, level, trump)
	_add_threat(Card.Suit.NONE, Card.RANK_SMALL_JOKER, level, trump)
	_add_threat(Card.Suit.NONE, Card.RANK_BIG_JOKER, level, trump)
	return _threats


func _add_threat(suit: int, rank: int, level: int, trump: int) -> void:
	var card := Card.create(suit, rank)
	_threats.append({"suit": suit, "rank": rank,
		"power": Play.power(card, level, trump), "trump": Play.is_trump(card, level, trump)})


# 扣底优先序：非分副牌 < 分牌副牌 < 非分主牌 < 分牌主牌，同级牌力小者优先扣出。
func _discard_key(card: Card, level: int, trump: int) -> int:
	var key := Play.power(card, level, trump)
	if card.score_value() > 0:
		key += 1000
	if Play.is_trump(card, level, trump):
		key += 2000
	return key


# 若主花色为 suit，手牌中的主牌张数（规则 §3）。
func _trump_count_if(hand: Array[Card], suit: int) -> int:
	var count := 0
	for card in hand:
		if Play.is_trump(card, _level, suit):
			count += 1
	return count


func _bid_threshold(kind: int) -> int:
	match kind:
		Bidding.Kind.BIG_JOKERS_3, Bidding.Kind.SMALL_JOKERS_3:
			return 0  # 规则 §4.3：3 王亮可任意定主，必叫
		Bidding.Kind.LEVEL_3:
			return BID_LEVEL_3_MIN
		Bidding.Kind.LEVEL_2:
			return BID_LEVEL_2_MIN
	return BID_LEVEL_1_MIN


func _top_non_score(hand: Array[Card], level: int, trump: int, count: int) -> Array[Card]:
	var candidates: Array[Card] = []
	for card in hand:
		if card.score_value() == 0:
			candidates.append(card)
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) > Play.power(b, level, trump))
	return candidates.slice(0, count)  # 规则 §5：贡牌 = 手中最大的非分牌


func _first_action(round_state: RoundState, seat: int, type: int) -> Dictionary:
	for action in round_state.get_available_actions(seat):
		if action.get("type") == type:
			return action
	return {}


func _key_of(card: Card) -> String:
	return "%d:%d" % [card.suit, card.rank]


func _group_by_card(cards: Array[Card]) -> Dictionary:
	var groups := {}
	for card in cards:
		var key := _key_of(card)
		if not groups.has(key):
			var copies: Array[Card] = []
			groups[key] = copies
		groups[key].append(card)
	return groups


func _count_in_hand(hand: Array[Card], suit: int, rank: int) -> int:
	var count := 0
	for card in hand:
		if card.suit == suit and card.rank == rank:
			count += 1
	return count


func _remove_identical(cards: Array[Card], card: Card) -> void:
	for i in cards.size():
		if cards[i].is_identical(card):
			cards.remove_at(i)
			return
