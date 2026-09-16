extends RefCounted
## RoundState 集成测试：脚本化动作模拟完整一局。
## 覆盖：含进贡的整局（分数守恒）、非法动作拒绝、首局抢亮大王、首局翻底牌定庄、
## 无人亮主底牌定主、干锅、抠底。

const A := RoundState.ActionType
const P := RoundState.Phase
const S := Card.Suit.SPADE
const H := Card.Suit.HEART
const D := Card.Suit.DIAMOND
const CL := Card.Suit.CLUB


func run(c: TestCheck) -> void:
	_full_round_with_tribute(c)
	_illegal_actions(c)
	_first_round_grab_joker(c)
	_first_round_flip_bottom(c)
	_no_bid_trump_from_bottom(c)
	_dry_pot(c)
	_kongdi(c)


# 含亮主、进贡、扣底、出牌到结算的完整一局（后续局，S=75 → 贡 2 张）。
func _full_round_with_tribute(c: TestCheck) -> void:
	var rs := RoundState.new({
		"is_first_round": false, "dealer_side": 0, "dealer_level": 6, "catcher_level": 4,
		"tribute_score": 75, "seed": 20260309,
	})
	c.check_eq(rs.get_phase(), P.DEALING, "初始阶段 DEALING")
	_deal_all(rs)
	c.check_eq(rs.get_phase(), P.BIDDING, "发完牌进入 BIDDING")
	for seat in 4:
		c.check_eq(rs.get_hand(seat).size(), 39, "每人 39 张手牌")
	c.check_eq(rs.get_bottom().size(), 6, "底牌 6 张")

	var bidder := -1
	var bid_suit := -1
	for seat in 4:
		for card in rs.get_hand(seat):
			if card.rank == 6:
				bidder = seat
				bid_suit = card.suit
				break
		if bidder >= 0:
			break
	c.check_true(bidder >= 0, "162 张牌必有级牌可亮")
	c.check_true(rs.apply_action(bidder, {"type": A.BID, "kind": Bidding.Kind.LEVEL_1, "suit": bid_suit}),
		"§4.3 亮 1 张级牌合法")
	c.check_true(rs.close_bidding(), "倒计时关闭亮主窗口")
	c.check_eq(rs.get_trump_suit(), bid_suit, "亮主花色即主花色")
	c.check_eq(rs.get_level(), 6, "级牌 = 庄家方级别")
	var dealer := rs.get_dealer_seat()
	c.check_true(RoundState.side_of(dealer) == 0, "庄家属于庄家方")
	if RoundState.side_of(bidder) == 0:
		c.check_eq(dealer, bidder, "§10 庄家方成员亮主成功由其坐庄")

	c.check_eq(rs.get_phase(), P.TRIBUTE, "定主后进入进贡")
	var payers := RoundState.side_seats(1)
	c.check_true(rs.apply_action(payers[0], {"type": A.TRIBUTE, "cards": []}), "§5 首张贡手可贡 0 张")
	var offered := _top_non_score(rs, payers[1], 2)
	c.check_true(rs.apply_action(payers[1], {"type": A.TRIBUTE, "cards": offered}),
		"§5 末位贡手补足 2 张最大非分牌（75 分 → 2 张）")
	var returns := _return_candidates(rs, dealer, 2)
	c.check_true(rs.apply_action(dealer, {"type": A.RETURN, "to_seat": payers[1], "cards": returns}),
		"§5 庄家按贡数返还非分副牌")
	for seat in 4:
		if seat != dealer:
			c.check_eq(rs.get_hand(seat).size(), 39, "进贡还贡后抓分方手牌仍 39 张")

	c.check_eq(rs.get_phase(), P.BOTTOM, "还贡完进入扣底")
	c.check_eq(rs.get_hand(dealer).size(), 45, "庄家拿底牌后 45 张")
	var discarded := _first_non_jokers(rs.get_hand(dealer), 6)
	c.check_true(rs.apply_action(dealer, {"type": A.DISCARD_BOTTOM, "cards": discarded}), "庄家扣底 6 张")
	c.check_false(rs.is_bottom_public(), "§6.1 无王扣底底牌不公开")
	for i in range(1, 4):
		var seat := (dealer + i) % 4
		c.check_true(rs.apply_action(seat, {"type": A.PASS}), "其他三家放弃扣王")
	c.check_eq(rs.get_phase(), P.PLAYING, "扣底结束进入出牌")
	c.check_eq(rs.get_current_seat(), dealer, "§10 第一轮由庄家领出")

	_auto_play(rs, c)
	c.check_eq(rs.get_phase(), P.SETTLEMENT, "39 轮打完进入结算")
	for seat in 4:
		c.check_true(rs.get_hand(seat).is_empty(), "手牌全部打空")
	var r := rs.get_result()
	var in_play: Array = r.in_play_scores
	c.check_eq(in_play[0] + in_play[1] + r.bottom_score, 300, "分数守恒：桌面分 + 底牌分 = 300")
	var catcher: int = 1 - r.dealer_side
	var expected_s: int = in_play[catcher] + (2 * r.bottom_score if r.kongdi else 0)
	c.check_eq(r.catcher_score, expected_s, "§8 S = 抓分方总分（含抠底翻倍）")
	c.check_true(r.next_dealer_side in [0, 1], "结果含下局庄家方")
	c.check_true(r.has("next_tribute") and r.next_tribute.has("score"), "结果含下局进贡参数")


# 非法动作（非当前座位、不合规则的牌/叫价）被拒绝且状态不变。
func _illegal_actions(c: TestCheck) -> void:
	var rs := RoundState.new({
		"is_first_round": false, "dealer_side": 0, "dealer_level": 6, "catcher_level": 4,
		"tribute_score": 90, "seed": 777,
	})
	c.check_false(rs.apply_action(0, {"type": A.BID, "kind": Bidding.Kind.LEVEL_2, "suit": S}),
		"未摸到牌时叫价非法")
	c.check_false(rs.apply_action(0, {"type": A.PLAY, "cards": []}), "发牌阶段不能出牌")
	c.check_false(rs.close_bidding(), "DEALING 阶段不能关亮主窗口")
	_deal_all(rs)

	var available := rs.get_available_actions(0)
	var illegal_bid := {}
	for kind in [Bidding.Kind.BIG_JOKERS_3, Bidding.Kind.SMALL_JOKERS_3, Bidding.Kind.LEVEL_3, Bidding.Kind.LEVEL_2]:
		var candidate := {"type": A.BID, "kind": kind, "suit": CL}
		if not _action_in(available, candidate):
			illegal_bid = candidate
			break
	if not illegal_bid.is_empty():
		c.check_false(rs.apply_action(0, illegal_bid), "超出合法叫价表的叫价被拒绝")

	rs.close_bidding()
	var dealer := rs.get_dealer_seat()
	var payers := RoundState.side_seats(1)
	var non_payer: int = RoundState.side_seats(0)[0]
	c.check_false(rs.apply_action(non_payer, {"type": A.TRIBUTE, "cards": []}), "非贡手不能进贡")
	var hand1_before := rs.get_hand(payers[0]).size()
	var score_card := _find_card(rs.get_hand(payers[0]), func(card: Card) -> bool: return card.score_value() > 0)
	if score_card != null:
		c.check_false(rs.apply_action(payers[0], {"type": A.TRIBUTE, "cards": [score_card]}), "§5 贡牌不能是分牌")
		c.check_eq(rs.get_hand(payers[0]).size(), hand1_before, "非法进贡后手牌不变")
	rs.apply_action(payers[0], {"type": A.TRIBUTE, "cards": []})
	rs.apply_action(payers[1], {"type": A.TRIBUTE, "cards": _top_non_score(rs, payers[1], 1)})
	c.check_false(rs.apply_action(dealer, {"type": A.RETURN, "to_seat": payers[1], "cards": []}), "还贡张数必须等于贡数")
	var bad_return := _find_card(rs.get_hand(dealer),
		func(card: Card) -> bool: return card.score_value() > 0 or Play.is_trump(card, rs.get_level(), rs.get_trump_suit()))
	if bad_return != null:
		c.check_false(rs.apply_action(dealer, {"type": A.RETURN, "to_seat": payers[1], "cards": [bad_return]}),
			"§5 还贡必须是非分副牌")
	rs.apply_action(dealer, {"type": A.RETURN, "to_seat": payers[1], "cards": _return_candidates(rs, dealer, 1)})

	c.check_false(rs.apply_action(payers[0], {"type": A.DISCARD_BOTTOM, "cards": _first_non_jokers(rs.get_hand(payers[0]), 6)}),
		"非庄家不能扣底")
	c.check_false(rs.apply_action(dealer, {"type": A.DISCARD_BOTTOM, "cards": _first_non_jokers(rs.get_hand(dealer), 5)}),
		"扣底必须 6 张")
	rs.apply_action(dealer, {"type": A.DISCARD_BOTTOM, "cards": _first_non_jokers(rs.get_hand(dealer), 6)})
	c.check_false(rs.apply_action(dealer, {"type": A.DISCARD_BOTTOM, "cards": _first_non_jokers(rs.get_hand(dealer), 6)}),
		"不能重复扣底")
	for i in range(1, 4):
		rs.apply_action((dealer + i) % 4, {"type": A.PASS})

	var leader := rs.get_current_seat()
	var wrong_seat := (leader + 1) % 4
	var wrong_hand_before := rs.get_hand(wrong_seat).size()
	c.check_false(rs.apply_action(wrong_seat, {"type": A.PLAY, "cards": [rs.get_hand(wrong_seat)[0]]}),
		"非当前座位不能出牌")
	c.check_eq(rs.get_hand(wrong_seat).size(), wrong_hand_before, "非法出牌后手牌不变")
	c.check_eq(rs.get_current_seat(), leader, "非法出牌后出牌权不变")
	var lead_hand := rs.get_hand(leader)
	c.check_false(rs.apply_action(leader, {"type": A.PLAY, "cards": [lead_hand[0], lead_hand[1], lead_hand[2], lead_hand[3]]}),
		"§7.1 禁止 4 张牌型（甩牌）")
	var mixed: Array[Card] = []
	for card in lead_hand:
		if mixed.is_empty() or not mixed[0].same_card(card):
			mixed.append(card)
		if mixed.size() == 2:
			break
	if mixed.size() == 2:
		c.check_false(rs.apply_action(leader, {"type": A.PLAY, "cards": mixed}), "§7.1 两张不同牌不是棒子")
	rs.apply_action(leader, {"type": A.PLAY, "cards": [lead_hand[0]]})
	var ghost := Card.create(S, 9, 0)
	c.check_false(rs.apply_action(wrong_seat, {"type": A.PLAY, "cards": [ghost]}), "不能出手中没有的牌")


# 首局：发牌过程中抢亮大王定庄定主，跳过 BIDDING 与 TRIBUTE（§4.2、§5）。
func _first_round_grab_joker(c: TestCheck) -> void:
	var rs := RoundState.new({"is_first_round": true, "seed": 20260310})
	var bidder := -1
	while rs.get_phase() == P.DEALING:
		if bidder == -1:
			for seat in 4:
				for action in rs.get_available_actions(seat):
					if action.get("kind") == Bidding.Kind.FIRST_ROUND_JOKER:
						c.check_true(rs.apply_action(seat, action), "§4.2 抓到大王可抢亮")
						bidder = seat
						break
				if bidder >= 0:
					break
		rs.apply_action(0, {"type": A.DEAL})
	c.check_true(bidder >= 0, "该种子下有人摸到大王")
	c.check_eq(rs.get_phase(), P.BOTTOM, "首局定庄后直接进入扣底（跳过亮主窗口与进贡）")
	c.check_eq(rs.get_dealer_seat(), bidder, "§4.2 抢亮大王者坐庄")
	c.check_eq(rs.get_dealer_side(), RoundState.side_of(bidder), "首局庄家方 = 抢亮者一方")
	c.check_eq(rs.get_level(), 3, "首局打 3")
	var hand: Array[Card] = rs.get_hand(bidder)
	var joker_idx := -1
	for i in hand.size():
		if hand[i].is_big_joker():
			joker_idx = i
			break
	var expected_suit := Bidding.first_round_trump_suit(hand.slice(joker_idx + 1))
	if expected_suit != Bidding.SUIT_UNDECIDED:
		c.check_eq(rs.get_trump_suit(), expected_suit, "§4.2 之后摸到的第一张花色牌定主")
	else:
		c.check_true(rs.get_trump_suit() in [S, H, D, CL], "之后全摸王的极端情形兜底定主")
	_auto_bottom(rs)
	_auto_play(rs)
	c.check_eq(rs.get_phase(), P.SETTLEMENT, "首局可完整打完")
	var r := rs.get_result()
	c.check_eq(r.in_play_scores[0] + r.in_play_scores[1] + r.bottom_score, 300, "首局分数守恒")


# 首局无人亮大王：翻底牌比大小定庄（3 张大王全排在底牌）。
func _first_round_flip_bottom(c: TestCheck) -> void:
	var normals: Array[Card] = []
	var bigs: Array[Card] = []
	for card in Deck.build():
		if card.is_big_joker():
			bigs.append(card)
		else:
			normals.append(card)
	normals.append_array(bigs)  # 底牌 = normals[156..158] + 3 张大王
	var rs := RoundState.new({"is_first_round": true, "deck": normals, "seed": 5})
	_deal_all(rs)
	c.check_eq(rs.get_phase(), P.BOTTOM, "无人亮大王翻底牌后进入扣底")
	c.check_eq(rs.get_dealer_seat(), 3, "§4.2 翻出最大牌（大王）的座位 3 为庄")
	c.check_eq(rs.get_dealer_side(), 1, "庄家方随之确定")
	c.check_eq(rs.get_trump_suit(), normals[156].suit, "翻到大王时以底牌首张花色牌定主（兜底）")


# 后续局无人亮主：从底牌抽花色牌定主（§4.3）。
func _no_bid_trump_from_bottom(c: TestCheck) -> void:
	var rs := RoundState.new({
		"is_first_round": false, "dealer_side": 0, "dealer_level": 6, "catcher_level": 4,
		"tribute_score": 100, "seed": 42,
	})
	_deal_all(rs)
	c.check_true(rs.close_bidding(), "无人亮主可直接关窗口")
	c.check_true(rs.get_trump_suit() in [S, H, D, CL], "§4.3 无人亮主从底牌定主")
	c.check_true(rs.get_dealer_seat() in [0, 2], "§10 庄家仍属庄家方")


# 干锅：扣王后底牌公开且全主（小王 + 主花色牌），底牌冻结、王奖励作废（§6.4）。
func _dry_pot(c: TestCheck) -> void:
	var deck := Deck.shuffled(20260311)
	var placed: Array[int] = []
	var bottom_cards: Array[Card] = []
	bottom_cards.append(_place_card(deck, 156, Card.Suit.NONE, Card.RANK_SMALL_JOKER, placed))
	var ranks := [3, 4, 5, 7, 8]
	for k in range(1, 6):
		bottom_cards.append(_place_card(deck, 156 + k, S, ranks[k - 1], placed))
	_place_card(deck, 0, S, 6, placed)  # 座位 0 必有 ♠6 可亮主
	# 3 张大王放进座位 1 手中：庄家无大王才能先扣小王（§6.2）
	_place_card(deck, 1, Card.Suit.NONE, Card.RANK_BIG_JOKER, placed)
	_place_card(deck, 5, Card.Suit.NONE, Card.RANK_BIG_JOKER, placed)
	_place_card(deck, 9, Card.Suit.NONE, Card.RANK_BIG_JOKER, placed)
	var rs := RoundState.new({
		"is_first_round": false, "dealer_side": 0, "dealer_level": 6, "catcher_level": 4,
		"tribute_score": 100, "deck": deck, "seed": 9,
	})
	_deal_all(rs)
	c.check_true(rs.apply_action(0, {"type": A.BID, "kind": Bidding.Kind.LEVEL_1, "suit": S}), "座位 0 亮 ♠6")
	rs.close_bidding()
	c.check_eq(rs.get_dealer_seat(), 0, "庄家方成员亮主成功由其坐庄")
	_auto_tribute(rs)
	c.check_true(rs.apply_action(0, {"type": A.DISCARD_BOTTOM, "cards": bottom_cards}), "庄家扣底（含小王）")
	c.check_true(rs.is_bottom_public(), "§6.1 扣了王底牌必须亮明")
	c.check_true(rs.is_dry_pot(), "§6.4 底牌全主判定干锅")
	c.check_eq(rs.get_phase(), P.PLAYING, "干锅后不再扣王直接出牌")
	_auto_play(rs)
	var r := rs.get_result()
	c.check_true(r.dry_pot, "结果标记干锅")
	c.check_false(r.next_tribute.bonus_active, "§6.4 干锅局王奖励（血）作废")
	if r.branch == 7:
		c.check_eq(r.dealer_level, 7, "§8 干锅分支 7 仅升 1 级，王追加升级作废")
	c.check_eq(r.in_play_scores[0] + r.in_play_scores[1] + r.bottom_score, 300, "干锅局分数守恒")


# 抠底变体：扫描固定种子找到末轮抓分方赢的局，验证底牌分翻倍与结算（§8）。
func _kongdi(c: TestCheck) -> void:
	var found := false
	for seed in range(1, 80):
		var rs := RoundState.new({
			"is_first_round": false, "dealer_side": 0, "dealer_level": 6, "catcher_level": 4,
			"tribute_score": 100, "seed": seed,
		})
		_deal_all(rs)
		rs.close_bidding()
		_auto_tribute(rs)
		_auto_bottom(rs)
		_auto_play(rs)
		var r := rs.get_result()
		if r.get("kongdi", false):
			found = true
			var catcher: int = 1 - r.dealer_side
			c.check_eq(r.catcher_score, r.in_play_scores[catcher] + 2 * r.bottom_score,
				"§8 抠底：底牌分翻 2 倍计入 S")
			c.check_true(r.branch in [2, 3, 4, 6], "抠底局只可能走分支 2/3/4/6")
			c.check_eq(r.in_play_scores[0] + r.in_play_scores[1] + r.bottom_score, 300, "抠底局分数守恒")
			break
	c.check_true(found, "固定种子扫描内出现抠底局")


func _deal_all(rs: RoundState) -> void:
	while rs.get_phase() == P.DEALING:
		rs.apply_action(0, {"type": A.DEAL})


# 自动进贡/还贡：首张贡手贡 0 张，末位补足；庄家以手中最小的非分副牌还贡。
func _auto_tribute(rs: RoundState) -> void:
	while rs.get_phase() == P.TRIBUTE:
		var acted := false
		for seat in 4:
			var actions := rs.get_available_actions(seat)
			if actions.is_empty():
				continue
			var action: Dictionary = actions[0]
			if action.type == A.TRIBUTE:
				rs.apply_action(seat, {"type": A.TRIBUTE, "cards": _top_non_score(rs, seat, action.min_count)})
			elif action.type == A.RETURN:
				rs.apply_action(seat, {"type": A.RETURN, "to_seat": action.to_seat,
					"cards": _return_candidates(rs, seat, action.count)})
			acted = true
			break
		if not acted:
			break


# 自动扣底：庄家扣手中前 6 张非王牌（底牌不公开），其他三家放弃扣王。
func _auto_bottom(rs: RoundState) -> void:
	while rs.get_phase() == P.BOTTOM:
		var acted := false
		for seat in 4:
			var actions := rs.get_available_actions(seat)
			if actions.is_empty():
				continue
			var action: Dictionary = actions[0]
			if action.type == A.DISCARD_BOTTOM:
				rs.apply_action(seat, {"type": A.DISCARD_BOTTOM, "cards": _first_non_jokers(rs.get_hand(seat), 6)})
			else:
				rs.apply_action(seat, {"type": A.PASS})
			acted = true
			break
		if not acted:
			break


# 自动出牌：首家领出手中第一张（单张），跟牌按规则 §7.2 选合法牌。
func _auto_play(rs: RoundState, c: TestCheck = null) -> void:
	while rs.get_phase() == P.PLAYING:
		var seat := rs.get_current_seat()
		var hand := rs.get_hand(seat)
		var plays := rs.get_table_plays()
		var cards: Array[Card] = []
		if plays.is_empty():
			cards.append(hand[0])
		else:
			cards = _follow_cards(hand, plays[0].cards, rs.get_level(), rs.get_trump_suit())
		var ok := rs.apply_action(seat, {"type": A.PLAY, "cards": cards})
		if c != null:
			c.check_true(ok, "自动出牌须合法")
		elif not ok:
			break


func _follow_cards(hand: Array[Card], lead: Array[Card], level: int, trump: int) -> Array[Card]:
	var n := lead.size()
	var lead_trump := Play.is_trump(lead[0], level, trump)
	var group: Array[Card] = []
	var rest: Array[Card] = []
	for card in hand:
		var in_group: bool
		if lead_trump:
			in_group = Play.is_trump(card, level, trump)
		else:
			in_group = card.suit == lead[0].suit and not Play.is_trump(card, level, trump)
		if in_group:
			group.append(card)
		else:
			rest.append(card)
	var chosen: Array[Card] = []
	for i in mini(n, group.size()):
		chosen.append(group[i])
	var idx := 0
	while chosen.size() < n:
		chosen.append(rest[idx])
		idx += 1
	return chosen


func _top_non_score(rs: RoundState, seat: int, n: int) -> Array[Card]:
	var candidates: Array[Card] = []
	for card in rs.get_hand(seat):
		if card.score_value() == 0:
			candidates.append(card)
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, rs.get_level(), rs.get_trump_suit()) > Play.power(b, rs.get_level(), rs.get_trump_suit()))
	var result: Array[Card] = []
	for i in mini(n, candidates.size()):
		result.append(candidates[i])
	return result


func _return_candidates(rs: RoundState, seat: int, n: int) -> Array[Card]:
	var result: Array[Card] = []
	for card in rs.get_hand(seat):
		if card.score_value() == 0 and not Play.is_trump(card, rs.get_level(), rs.get_trump_suit()):
			result.append(card)
			if result.size() == n:
				break
	return result


func _first_non_jokers(hand: Array[Card], n: int) -> Array[Card]:
	var result: Array[Card] = []
	for card in hand:
		if not card.is_joker():
			result.append(card)
			if result.size() == n:
				break
	return result


func _find_card(hand: Array[Card], predicate: Callable) -> Card:
	for card in hand:
		if predicate.call(card):
			return card
	return null


func _action_in(actions: Array, target: Dictionary) -> bool:
	for action in actions:
		if action.get("kind") == target.get("kind") and action.get("suit") == target.get("suit"):
			return true
	return false


# 把指定花色点数的牌交换到 deck[pos]（不碰 placed 中已占位的槽），返回该牌对象。
func _place_card(deck: Array[Card], pos: int, suit: int, rank: int, placed: Array[int]) -> Card:
	for i in deck.size():
		if i in placed:
			continue
		var card: Card = deck[i]
		if card.suit == suit and card.rank == rank:
			deck[i] = deck[pos]
			deck[pos] = card
			placed.append(pos)
			return card
	return null
