class_name HeuristicAI
extends AIPlayer
## 启发式 AI：逐张记牌 + 缺门跟踪（已出副本计数 + 绝门推导）+ 阈值策略。
## 策略参考打滚子技巧（扣底净门 / 不滥扣分 / 藏 A 留棒 / 记牌信邪 / 尾盘抢攻 /
## 吊主抽主 / 跑分捡分 / 没分不杀）：
## - 亮主/反主：按拟任主花色下的主牌长度阈值（规则 §4），打 10 无血不叫（阈值 +1）；
##   3 王亮必叫并选最强花色。
## - 进贡：贡手中最大的非分牌；多张时首贡手贡一半（向下取整）、末位补足（§5 约定分摊）。
## - 还贡：最小的非分副牌（§5）。
## - 扣底：优先把某门副牌整门扣净造缺门（技巧 1）；非分牌够且主牌不强时不扣分牌
##   （技巧 2）；主牌够强时扣王赌保底（§6.2 先大王后小王），留副牌防干锅（§6.4）。
## - 其他家扣王：庄家方加码已亮底的底牌；抓分方主牌够强时扣王赌抠底（§8 分支4/分支3）。
## - 领出：主牌占剩余主牌一半以上且对手未全绝主时先吊主（经验一/二：先吊主后打副、
##   瓦解对手主牌威胁；倒着出，有大王绝不先出小王；优先主牌滚子/棒子双调抽得更快）；
##   否则领"无人能压"的滚子/棒子（记牌 + 缺门判定，技巧 4）；再试安全大牌单张
##   （抓分方优先分牌跑分，庄家方优先非分大牌；该门手牌 ≥2 才出——技巧 6"A"：
##   吃那门/剩一张时不要轻动）；都不行则非分小牌单张试探（不拆棒、优先对手未绝门的，
##   技巧 3/4）。
## - 跟牌：能赢则以最小代价赢，优先不拆自家棒/滚子的赢法（技巧 3 留棒、技巧 7
##   因式分解不分解自家牌式）；桌面无分且非尾盘时放弃主杀副、拆棒、动"头"的赢法
##   （"有分杀没分跑"、不为拔货上 2 和 3、不轻易把头给出——A/K 两个头基本控制一门）；
##   队友已赢则喂分（§7.3 赢家收走桌面分牌）；赢不了垫最小的非分孤张（不拆棒）。
## - 尾盘（手牌 ≤6）直接出最大牌型抢出牌权（技巧 8 先下手为强）。

const BID_LEVEL_1_MIN := 16  # 亮 1 张级牌所需拟任主花色下的主牌张数
const BID_LEVEL_2_MIN := 15
const BID_LEVEL_3_MIN := 14
const REBID_EXTRA := 1  # 反主（已有人叫价）时的阈值加成
const BID_LEVEL_10_EXTRA := 1  # 打 10 无血不叫：级牌为 10 时的阈值加成
const TRUMP_PULL_MIN := 6  # 吊主所需最低主牌张数（防中残局小样本误判）
const BOTTOM_JOKER_TRUMP_MIN := 20  # 庄家扣王赌保底所需的主牌张数（45 张中）
const CATCHER_JOKER_TRUMP_MIN := 18  # 抓分方扣王赌抠底所需的主牌张数（39 张中）
const ENDGAME_HAND := 6  # 手牌 ≤ 6 进入尾盘：直接出最大牌型抢出牌权（技巧 8）
const DECK_COPIES := 3  # 每种牌 3 个副本（3 副牌）
const PAIR_KEEP_PENALTY := 100  # 垫牌排序中"拆棒"的惩罚（约一个主牌层级，技巧 3 留棒）
const PAD_SCORE_PENALTY := 100000  # 垫牌排序中分牌的惩罚（必须压过一切非分牌）

var _level := 3
var _trump := Bidding.SUIT_UNDECIDED  # 定主后由 decide_* 同步（observe_play 拿不到 round_state）
var _played := {}  # "suit:rank" -> 已打出副本数
var _voids := {}  # seat -> {"suit:<suit>"/"trump": true}：该座位已绝的门（技巧 4 记缺门）
var _trick_buf: Array = []  # 当前轮已出的 {"seat","cards"}，用于绝门判定
var _threats: Array = []  # 全牌表缓存：{"suit","rank","power","trump"}，按 level+trump 记忆
var _threats_key := ""


func start_round(round_state: RoundState, _seat: int) -> void:
	_level = round_state.get_level()
	_trump = Bidding.SUIT_UNDECIDED
	_played.clear()
	_voids.clear()
	_trick_buf.clear()
	_threats_key = ""


func observe_play(seat: int, cards: Array[Card]) -> void:
	for card in cards:
		var key := _key_of(card)
		_played[key] = _played.get(key, 0) + 1
	if _trick_buf.size() >= RoundState.PLAYER_COUNT:
		_trick_buf.clear()
	if not _trick_buf.is_empty() and _trump != Bidding.SUIT_UNDECIDED:
		_observe_voids(seat, cards)
	_trick_buf.append({"seat": seat, "cards": cards})


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
	if _level == 10:
		extra += BID_LEVEL_10_EXTRA  # 打 10 没有血的情况下尽量不要打（捡分经验 1）
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
	_sync_trump(round_state)
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
	# 技巧 2：非分牌够扣且主牌没强到稳保底时，分牌不入底
	var allow_score := trump_count >= BOTTOM_JOKER_TRUMP_MIN \
		or _count_non_score(hand) < Deck.BOTTOM_SIZE
	_bury_whole_suit(picked, rest, level, trump, allow_score)  # 技巧 1：整门扣净造缺门
	_fill_bottom(picked, rest, level, trump, allow_score)
	if picked.size() < Deck.BOTTOM_SIZE:
		_fill_bottom(picked, rest, level, trump, true)  # 极端手牌：放宽分牌限制补满
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
	_sync_trump(round_state)
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
	_sync_trump(round_state)
	var hand := round_state.get_hand(seat)
	var level := round_state.get_level()
	var trump := round_state.get_trump_suit()
	var table := round_state.get_table_plays()
	var cards: Array[Card]
	if table.is_empty():
		var catcher := RoundState.side_of(seat) != round_state.get_dealer_side()
		cards = _lead(hand, seat, level, trump, catcher)
	else:
		cards = _follow(hand, table, seat, level, trump)
	return {"type": RoundState.ActionType.PLAY, "cards": cards}


func _lead(hand: Array[Card], seat: int, level: int, trump: int, catcher: bool) -> Array[Card]:
	if hand.size() <= ENDGAME_HAND:
		return _strongest_combo(hand, level, trump)  # 技巧 8 尾盘：最大牌型抢抠底/保底
	var pull := _trump_pull(hand, seat, level, trump)
	if not pull.is_empty():
		return pull  # 经验一/二：主牌长则先吊主后打副
	for size in [DECK_COPIES, 2]:
		var combo := _best_safe_combo(hand, size, seat, level, trump)
		if not combo.is_empty():
			return combo
	var single := _safe_high_single(hand, seat, level, trump, catcher)
	if single != null:
		return [single]
	return [_probe(hand, seat, level, trump)]


# 吊主（经验一/二）：手中主牌占剩余主牌一半以上（主牌长）且对手未全绝主时，
# 领出主牌抽主，瓦解对手主牌威胁；对手全绝主则瓦解完成，改打副牌。
# 倒着出：优先最大的主牌滚子/棒子（双调抽得更快），否则最大单张主（有大王绝不先出小王）。
func _trump_pull(hand: Array[Card], seat: int, level: int, trump: int) -> Array[Card]:
	var opps := _opponents(seat)
	if _seat_void_trump(opps[0]) and _seat_void_trump(opps[1]):
		return []
	var mine: Array[Card] = []
	for card in hand:
		if Play.is_trump(card, level, trump):
			mine.append(card)
	if mine.size() < TRUMP_PULL_MIN:
		return []
	if mine.size() * 2 < _unseen_trumps(hand, level, trump):
		return []  # 主牌不够长：主短副强时应以出副牌为主（经验三/四）
	var groups := _group_by_card(mine)
	for size in [DECK_COPIES, 2]:
		var best: Array[Card] = []
		for key in groups:
			var copies: Array[Card] = groups[key]
			if copies.size() >= size and (best.is_empty() or
					Play.power(copies[0], level, trump) > Play.power(best[0], level, trump)):
				best = copies.slice(0, size)
		if not best.is_empty():
			return best
	var top := mine[0]
	for card in mine:
		if Play.power(card, level, trump) > Play.power(top, level, trump):
			top = card
	return [top]


# 不在我手中的剩余主牌总张数（已出副本计数推导，含对门与其他两家的）。
func _unseen_trumps(hand: Array[Card], level: int, trump: int) -> int:
	var total := 0
	for entry in _threat_table(level, trump):
		if entry.trump:
			total += _unseen(entry, hand)
	return total


# 领出安全大牌单张：记牌判定无人能压（技巧 4）。抓分方优先分牌跑分（捡分经验：
# 跑掉和灭掉足够的分），庄家方优先非分大牌（庄家方的分不入账，只跑对门的分）。
# 该门手牌 ≥2 才出——技巧 6"A"：吃那门（要靠主杀那门）或只剩一张时不要轻动，
# 防止 A 一出对方的 K 全活。
func _safe_high_single(hand: Array[Card], seat: int, level: int, trump: int,
		prefer_score: bool) -> Card:
	var suit_counts := {}
	for card in hand:
		if not Play.is_trump(card, level, trump):
			suit_counts[card.suit] = suit_counts.get(card.suit, 0) + 1
	var best: Card = null
	var best_key := -1
	for card in hand:
		if Play.is_trump(card, level, trump):
			continue
		if suit_counts[card.suit] < 2:
			continue
		if not _is_safe(card, 1, hand, seat, level, trump):
			continue
		var key := Play.power(card, level, trump)
		if (card.score_value() > 0) == prefer_score:
			key += 1000
		if key > best_key:
			best_key = key
			best = card
	return best


# 试探领出：不拆对子的最小非分副牌（优先对手未绝门的，技巧 4 记缺门）→
# 任意最小非分副牌 → 最小非分主牌 → 最小牌。
func _probe(hand: Array[Card], seat: int, level: int, trump: int) -> Card:
	var counts := _group_by_card(hand)
	var opps := _opponents(seat)
	for pass_no in 5:
		var best: Card = null
		for card in hand:
			var non_score := card.score_value() == 0
			var side := not Play.is_trump(card, level, trump)
			var single: bool = counts[_key_of(card)].size() == 1
			var ok: bool
			match pass_no:
				0:  # 对手未绝门：对手必须跟门，无法单张主杀
					ok = non_score and side and single and not _any_void(opps, card.suit)
				1:
					ok = non_score and side and single
				2:
					ok = non_score and side
				3:
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
		var wins := _winning_combos(group, table[best_idx].cards, n, level, trump)
		if not wins.is_empty():
			# 桌面有分或尾盘才放开杀（有分杀、抢抠底/保底）；否则没分跑
			var liberal := _table_score(table) > 0 or hand.size() <= ENDGAME_HAND
			var pick := _pick_win(wins, hand, lead_trump, liberal, level, trump)
			if not pick.is_empty():
				return pick  # §7.3 能赢则以最小代价赢
	var counts := _group_by_card(hand)
	var chosen: Array[Card] = []
	var must := mini(group.size(), n)
	chosen.append_array(_select_follow(group, must, winner == mate, counts, level, trump))
	chosen.append_array(_select_follow(rest, n - must, winner == mate, counts, level, trump))
	return chosen


# 规则 §7.2 的跟牌分组（与 Trick._in_lead_group 同口径）：首家为主则主牌一组，
# 否则该花色副牌一组（级牌与 2 是主牌，不算该花色副牌）。
func _in_lead_group(card: Card, lead_trump: bool, lead_suit: int, level: int, trump: int) -> bool:
	if lead_trump:
		return Play.is_trump(card, level, trump)
	return card.suit == lead_suit and not Play.is_trump(card, level, trump)


# 同牌型且能压过当前最大的所有组合（每组同牌取 n 张）。
func _winning_combos(group: Array[Card], best_cards: Array[Card], n: int,
		level: int, trump: int) -> Array:
	var wins: Array = []
	var groups := _group_by_card(group)
	for key in groups:
		var copies: Array[Card] = groups[key]
		if copies.size() < n:
			continue
		var combo: Array[Card] = copies.slice(0, n)
		if Play.beats(best_cards, combo, level, trump):
			wins.append(combo)
	return wins


# 从可赢组合中挑一手。技巧 3 留棒 / 技巧 7 因式分解（不分解自家牌式）：
# 优先不拆自家棒/滚子的赢法，同级取牌力最小者。
# 没分不杀（liberal 为假）：放弃主杀副、拆棒、动"头"的赢法，垫牌让对手继续领——
# "有分杀没分跑"、不为拔货上 2 和 3、不轻易把头给出（A/K 两个头基本控制一门）。
func _pick_win(wins: Array, hand: Array[Card], lead_trump: bool, liberal: bool,
		level: int, trump: int) -> Array[Card]:
	var counts := _group_by_card(hand)
	var best: Array[Card] = []
	var best_breaks := false
	for combo in wins:
		var card: Card = combo[0]
		var breaks: bool = counts[_key_of(card)].size() > combo.size()
		if not liberal:
			if breaks:
				continue
			if Play.is_trump(card, level, trump) and not lead_trump:
				continue  # 桌面无分不用主杀副（不轻易杀副牌）
			if _is_head(card, hand, level, trump):
				continue  # 桌面无分不动头，留着控制这一门
		if best.is_empty() or (best_breaks and not breaks) \
				or (breaks == best_breaks
					and Play.power(card, level, trump) < Play.power(best[0], level, trump)):
			best = combo
			best_breaks = breaks
	return best


# "头"判定：该门副牌（或主牌）中已不见比它更大的牌（未见的与手中都没有更大者）。
func _is_head(card: Card, hand: Array[Card], level: int, trump: int) -> bool:
	var card_power := Play.power(card, level, trump)
	var card_trump := Play.is_trump(card, level, trump)
	for entry in _threat_table(level, trump):
		if entry.power <= card_power:
			continue
		if card_trump:
			if not entry.trump:
				continue
		elif entry.trump or entry.suit != card.suit:
			continue
		if _unseen(entry, hand) + _count_in_hand(hand, entry.suit, entry.rank) > 0:
			return false
	return true


# 桌面已出牌的分值合计（赢家收走，§7.3）。
func _table_score(table: Array) -> int:
	var total := 0
	for play in table:
		for card in play.cards:
			total += card.score_value()
	return total


# 垫牌选 count 张：队友已赢则优先喂分（§7.3 赢家收走桌面分牌），
# 否则垫最小的非分孤张——拆棒加惩罚，尽量保住棒子（技巧 3 留棒）。
func _select_follow(cards: Array[Card], count: int, feed_score: bool, counts: Dictionary,
		level: int, trump: int) -> Array[Card]:
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
			return _pad_key(a, counts, level, trump) < _pad_key(b, counts, level, trump))
	return sorted.slice(0, count)


# 垫牌代价：分牌最重（绝不能压过非分牌），其次拆棒，同级牌力小者优先垫出。
func _pad_key(card: Card, counts: Dictionary, level: int, trump: int) -> int:
	var key := Play.power(card, level, trump)
	if counts[_key_of(card)].size() >= 2:
		key += PAIR_KEEP_PENALTY
	if card.score_value() > 0:
		key += PAD_SCORE_PENALTY
	return key


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
func _best_safe_combo(hand: Array[Card], size: int, seat: int, level: int, trump: int) -> Array[Card]:
	var best: Array[Card] = []
	var groups := _group_by_card(hand)
	for key in groups:
		var copies: Array[Card] = groups[key]
		if copies.size() < size:
			continue
		if _is_safe(copies[0], size, hand, seat, level, trump):
			if best.is_empty() or Play.power(copies[0], level, trump) > Play.power(best[0], level, trump):
				best = copies.slice(0, size)
	return best


func _is_safe(card: Card, size: int, hand: Array[Card], seat: int, level: int, trump: int) -> bool:
	for entry in _threats_to(card, seat, level, trump):
		if _unseen(entry, hand) >= size:
			return false
	return true


func _unseen(entry: Dictionary, hand: Array[Card]) -> int:
	return DECK_COPIES - int(_played.get("%d:%d" % [entry.suit, entry.rank], 0)) \
		- _count_in_hand(hand, entry.suit, entry.rank)


# 能压 card 的同牌型威胁牌表。技巧 4 记缺门：对手已绝主则不怕主杀，
# 已绝该副门则不怕同门更大的牌（队友不会压自家领出，只防两个对手）。
func _threats_to(card: Card, seat: int, level: int, trump: int) -> Array:
	var card_power := Play.power(card, level, trump)
	var card_trump := Play.is_trump(card, level, trump)
	var opps := _opponents(seat)
	var result: Array = []
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
		if entry.trump:
			if _seat_void_trump(opps[0]) and _seat_void_trump(opps[1]):
				continue
		elif not card_trump and _seat_void(opps[0], suit) and _seat_void(opps[1], suit):
			continue
		result.append(entry)
	return result


# 技巧 4 记缺门：跟牌中出现非首门组的牌（规则 §7.2 有门必跟，垫出即绝），
# 标记该座位绝了首门；缺门持续整局，用于安全/风险判定与试探选门。
func _observe_voids(seat: int, cards: Array[Card]) -> void:
	var lead: Array = _trick_buf[0].cards
	var lead_trump := Play.is_trump(lead[0], _level, _trump)
	for card in cards:
		if _in_lead_group(card, lead_trump, lead[0].suit, _level, _trump):
			continue
		if not _voids.has(seat):
			_voids[seat] = {}
		if lead_trump:
			_voids[seat]["trump"] = true
		else:
			_voids[seat]["suit:%d" % lead[0].suit] = true
		return


func _seat_void(seat: int, suit: int) -> bool:
	return _voids.get(seat, {}).has("suit:%d" % suit)


func _seat_void_trump(seat: int) -> bool:
	return _voids.get(seat, {}).has("trump")


func _any_void(opps: Array[int], suit: int) -> bool:
	return _seat_void(opps[0], suit) or _seat_void(opps[1], suit)


func _opponents(seat: int) -> Array[int]:
	return [(seat + 1) % RoundState.PLAYER_COUNT, (seat + 3) % RoundState.PLAYER_COUNT]


# 定主后同步主花色（observe_play 拿不到 round_state，靠 decide_* 提前同步）。
func _sync_trump(round_state: RoundState) -> void:
	var suit := round_state.get_trump_suit()
	if suit != Bidding.SUIT_UNDECIDED and suit != Card.Suit.NONE:
		_trump = suit


# 技巧 1：若某门副牌能整门扣进底（全部可扣且张数 ≤ 剩余底位），优先整门扣掉造缺门；
# 多门可选时挑张数最少、并列时牌力总和最小的门（扣得最干净、最不疼）。
func _bury_whole_suit(picked: Array[Card], rest: Array[Card], level: int, trump: int,
		allow_score: bool) -> void:
	var slots: int = Deck.BOTTOM_SIZE - picked.size()
	if slots <= 0:
		return
	var by_suit := {}
	for card in rest:
		if Play.is_trump(card, level, trump):
			continue  # 主牌不算"门"，不参与整门扣
		if not by_suit.has(card.suit):
			by_suit[card.suit] = []
		by_suit[card.suit].append(card)
	var best_suit := -1
	var best_key := 0
	for suit in by_suit:
		var cards: Array = by_suit[suit]
		if cards.size() > slots:
			continue
		if not allow_score:
			var has_score := false
			for card in cards:
				if card.score_value() > 0:
					has_score = true
					break
			if has_score:
				continue
		var key := cards.size() * 100000
		for card in cards:
			key += _discard_key(card, level, trump)
		if best_suit == -1 or key < best_key:
			best_suit = suit
			best_key = key
	if best_suit == -1:
		return
	for card in by_suit[best_suit]:
		picked.append(card)
		_remove_identical(rest, card)


# 按扣底优先序补足底牌；allow_score 为假时分牌不入底（技巧 2）。
func _fill_bottom(picked: Array[Card], rest: Array[Card], level: int, trump: int,
		allow_score: bool) -> void:
	var sorted := rest.duplicate()
	sorted.sort_custom(func(a: Card, b: Card) -> bool:
		return _discard_key(a, level, trump) < _discard_key(b, level, trump))
	for card in sorted:
		if picked.size() >= Deck.BOTTOM_SIZE:
			return
		if not allow_score and card.score_value() > 0:
			continue
		picked.append(card)
		_remove_identical(rest, card)


func _count_non_score(hand: Array[Card]) -> int:
	var count := 0
	for card in hand:
		if card.score_value() == 0:
			count += 1
	return count


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
