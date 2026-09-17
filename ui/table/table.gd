extends Control
## 牌桌场景（step-05 出牌交互 + step-06 流程 UI + step-07 比赛串联）。
## 亮主/反主（BidPanel，发牌中与定主倒计时内可点）、进贡/还贡（TributePanel）、
## 扣底/扣王/捡补偿（BottomPanel）、局结算（SettlementPanel）均为对话框交互；
## 所有可选动作来自 RoundState.get_available_actions，合法性由 apply_action 终判，UI 不做规则判断。
## 玩家座无 AI；比赛串联经 Game autoload（MatchState）：结算后 finish_round 推进并自动存档，
## 下一局 config 来自 Game.next_round_config()；右上“退出比赛”放弃当前局回主菜单。

const A := RoundState.ActionType
const P := RoundState.Phase
const PLAYER_SEAT := 0
const AI_SEATS := [1, 2, 3]
const SEAT_NAMES := ["南（你）", "西", "北（队友）", "东"]
const SIDE_NAMES := ["南北方（我方）", "东西方（对方）"]
const DEAL_INTERVAL := 0.5  # 规则 §4.1：发牌动画约 1 秒 2 张
const AI_THINK_MIN := 0.5
const AI_THINK_MAX := 1.0
const AUTO_STEP_DELAY := 0.4
const TRICK_COLLECT_DELAY := 0.9
const PLAY_TWEEN_TIME := 0.25
const BIDDING_SECONDS := 5.0  # 规则 §4.3：定主倒计时，每次亮/反重置
const BID_TICK := 0.1
const AI_BID_DELAY := 0.6
const TRUMP_ANNOUNCE_DELAY := 1.2
const HAND_WIDTH := 1200.0
const SELECT_LIFT := 16.0
const SEAT_ANCHORS := [Vector2(800, 800), Vector2(110, 450), Vector2(800, 90), Vector2(1490, 450)]
const TRICK_SLOTS := [Vector2(800, 580), Vector2(560, 430), Vector2(800, 290), Vector2(1040, 430)]
const DECK_POS := Vector2(800, 450)
const BID_PANEL_POS := Vector2(1250, 560)

var _rs: RoundState = null
var _ais: Dictionary = {}  # AI_SEATS 座位 -> HeuristicAI；玩家座无 AI
var _rng := RandomNumberGenerator.new()
var _generation := 0  # 重开一局时使未完成的 await 失效
var _bid_time_left := 0.0
var _ai_bid_pending := false
var _last_bid_text := ""
var _bottom_snapshot: Array[Card] = []  # 进入 BOTTOM 前的底牌（标记庄家扣底来源用）
var _round_prev_levels := {}  # 绝对 side -> 本局开始时级别（结算面板显示用）
var _tribute_total := 0
var _match_progress_applied := false  # 本局结果是否已提交 MatchState（防重复 finish_round）
var _exit_armed := false  # “退出比赛”二次确认

var _hand_views: Array[CardView] = []
var _selected: Array[CardView] = []
var _trick_views: Array = []  # 4 × Array[CardView]
var _bottom_views: Array[CardView] = []
var _player_turn := false

var _hand_area: Control
var _center_layer: Control
var _fx_layer: Control
var _score_label: Label
var _bottom_label: Label
var _status_label: Label
var _hint_label: Label
var _play_button: Button
var _exit_button: Button
var _seat_labels: Array[Label] = []
var _count_labels: Array[Label] = []
var _bid_panel: BidPanel
var _tribute_panel: TributePanel
var _bottom_panel: BottomPanel
var _settlement_panel: SettlementPanel


func _ready() -> void:
	_rng.randomize()
	_build_ui()
	var config := Game.next_round_config()
	if config.is_empty():
		Game.new_match()  # 比赛已结束（不应发生），开新比赛兜底
		return
	_start_round(config)


func _start_round(config: Dictionary) -> void:
	_generation += 1
	_match_progress_applied = false
	_exit_armed = false
	_exit_button.text = "退出比赛"
	_rs = RoundState.new(config)
	_ais.clear()
	for seat in AI_SEATS:
		var ai := HeuristicAI.new()
		ai.start_round(_rs, seat)
		_ais[seat] = ai
	_round_prev_levels.clear()
	if config.get("is_first_round", false):
		_round_prev_levels[0] = RoundState.FIRST_ROUND_LEVEL
		_round_prev_levels[1] = RoundState.FIRST_ROUND_LEVEL
		_tribute_total = 0
	else:
		var dealer_side := int(config.get("dealer_side", 0))
		_round_prev_levels[dealer_side] = int(config.get("dealer_level", RoundState.FIRST_ROUND_LEVEL))
		_round_prev_levels[1 - dealer_side] = int(config.get("catcher_level", RoundState.FIRST_ROUND_LEVEL))
		_tribute_total = Tribute.total_count(int(config.get("tribute_score", 0)),
			int(config.get("tribute_bonus_big", 0)), int(config.get("tribute_bonus_small", 0)),
			bool(config.get("tribute_bonus_active", false)))
	_player_turn = false
	_selected.clear()
	_clear_trick_views()
	for view in _bottom_views + _hand_views:
		if is_instance_valid(view):
			view.queue_free()
	_bottom_views.clear()
	_hand_views.clear()
	for child in _fx_layer.get_children():
		child.queue_free()
	_bid_panel.hide_panel()
	_tribute_panel.hide_panel()
	_bottom_panel.hide_panel()
	_settlement_panel.hide_panel()
	_bottom_snapshot = _rs.get_bottom()
	_last_bid_text = ""
	_set_status("发牌中…")
	_refresh_all()
	_run_dealing(_generation)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.3, 0.15)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	_center_layer = _make_layer()
	_hand_area = Control.new()
	_hand_area.position = SEAT_ANCHORS[PLAYER_SEAT]
	add_child(_hand_area)
	_fx_layer = _make_layer()
	_score_label = _make_label(Vector2(20, 16), Vector2(380, 60))
	_bottom_label = _make_label(Vector2(20, 80), Vector2(380, 28))
	_status_label = _make_label(Vector2(400, 648), Vector2(800, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label = _make_label(Vector2(400, 684), Vector2(800, 26), HORIZONTAL_ALIGNMENT_CENTER)
	_play_button = Button.new()
	_play_button.text = "出牌"
	_play_button.position = Vector2(1430, 770)
	_play_button.size = Vector2(140, 48)
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play_pressed)
	add_child(_play_button)
	_exit_button = Button.new()
	_exit_button.text = "退出比赛"
	_exit_button.position = Vector2(1470, 16)
	_exit_button.size = Vector2(110, 36)
	_exit_button.pressed.connect(_on_exit_pressed)
	add_child(_exit_button)
	var label_pos := [Vector2(1150, 856), Vector2(50, 380), Vector2(725, 16), Vector2(1430, 380)]
	for seat in RoundState.PLAYER_COUNT:
		_seat_labels.append(_make_label(label_pos[seat], Vector2(160, 26), HORIZONTAL_ALIGNMENT_CENTER))
		_count_labels.append(_make_label(label_pos[seat] + Vector2(0, 26), Vector2(160, 24),
			HORIZONTAL_ALIGNMENT_CENTER))
		_seat_labels[seat].text = SEAT_NAMES[seat]
	for i in RoundState.PLAYER_COUNT:
		_trick_views.append([])
	_bid_panel = BidPanel.new()
	_bid_panel.position = BID_PANEL_POS
	_bid_panel.bid_chosen.connect(_on_bid_chosen)
	add_child(_bid_panel)
	_tribute_panel = TributePanel.new()
	add_child(_tribute_panel)
	_bottom_panel = BottomPanel.new()
	add_child(_bottom_panel)
	_settlement_panel = SettlementPanel.new()
	_settlement_panel.continued.connect(_on_settlement_continued)
	_settlement_panel.menu_requested.connect(_on_settlement_menu)
	add_child(_settlement_panel)


func _make_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _make_label(pos: Vector2, p_size: Vector2,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = p_size
	label.horizontal_alignment = align
	add_child(label)
	return label


# --- 流程驱动（异步链，_generation 失效即静默退出） ---

func _run_dealing(gen: int) -> void:
	var dealt := 0
	while _rs.get_phase() == P.DEALING and gen == _generation:
		_rs.apply_action(0, {"type": A.DEAL})
		var seat := dealt % RoundState.PLAYER_COUNT
		dealt += 1
		_animate_deal(seat)
		for s in AI_SEATS:
			var bid: Dictionary = (_ais[s] as HeuristicAI).decide_bid(_rs, s)
			if not bid.is_empty() and _rs.apply_action(s, bid):
				_announce_bid(s, bid)
		_bottom_snapshot = _rs.get_bottom()
		if seat == PLAYER_SEAT:
			_refresh_hand()
		_refresh_seat_counts()
		_refresh_bid_panel()
		await get_tree().create_timer(DEAL_INTERVAL).timeout
	if gen != _generation:
		return
	_refresh_all()
	_run_pre_play(gen)


func _run_pre_play(gen: int) -> void:
	if _rs.get_phase() == P.BIDDING:
		await _run_bidding_window(gen)
		if gen != _generation:
			return
	_bid_panel.hide_panel()
	if _rs.get_trump_suit() >= 0:
		_set_status("定主：%s 主，级牌 %d；%s坐庄" % [CardView.SUIT_SYMBOLS[_rs.get_trump_suit()],
			_rs.get_level(), SEAT_NAMES[_rs.get_dealer_seat()]])
		_refresh_all()
		await get_tree().create_timer(TRUMP_ANNOUNCE_DELAY).timeout
	while gen == _generation and _rs.get_phase() == P.TRIBUTE:
		await _tribute_step(gen)
		_refresh_all()
		await get_tree().create_timer(AUTO_STEP_DELAY).timeout
	while gen == _generation and _rs.get_phase() == P.BOTTOM:
		await _bottom_step(gen)
		_refresh_all()
		await get_tree().create_timer(AUTO_STEP_DELAY).timeout
	if gen != _generation:
		return
	_refresh_all()
	if _rs.get_phase() == P.PLAYING:
		_advance_play(gen)


# 规则 §4.3：发牌后亮主/反主倒计时窗口，每次亮/反重置，超时 close_bidding()。
func _run_bidding_window(gen: int) -> void:
	_bid_time_left = BIDDING_SECONDS
	_ai_bid_pending = true
	_refresh_bid_panel()
	while gen == _generation and _rs.get_phase() == P.BIDDING:
		if _ai_bid_pending:
			_ai_bid_pending = false
			var bidder := _ai_bid_once()
			if bidder >= 0:
				_bid_time_left = BIDDING_SECONDS
				_ai_bid_pending = true
				_refresh_bid_panel()
				await get_tree().create_timer(AI_BID_DELAY).timeout
				continue
		await get_tree().create_timer(BID_TICK).timeout
		if gen != _generation or _rs.get_phase() != P.BIDDING:
			break
		_bid_time_left -= BID_TICK
		_bid_panel.set_countdown_text("定主倒计时 %.1f 秒（亮/反重置）" % maxf(_bid_time_left, 0.0))
		if _bid_time_left <= 0.0:
			_rs.close_bidding()


func _ai_bid_once() -> int:
	for seat in AI_SEATS:
		var bid: Dictionary = (_ais[seat] as HeuristicAI).decide_bid(_rs, seat)
		if not bid.is_empty() and _rs.apply_action(seat, bid):
			_announce_bid(seat, bid)
			return seat
	return -1


func _announce_bid(seat: int, bid: Dictionary) -> void:
	_last_bid_text = "%s %s" % [SEAT_NAMES[seat],
		BidPanel.bid_text(int(bid.get("kind")), int(bid.get("suit", -1)), _rs.get_level())]
	_set_status(_last_bid_text)


# TRIBUTE：找到当前有动作的座位；玩家座弹对话框，AI 座自动并展示结果。
func _tribute_step(gen: int) -> void:
	for seat in RoundState.PLAYER_COUNT:
		var actions := _rs.get_available_actions(seat)
		if actions.is_empty():
			continue
		var action_type := int(actions[0].get("type"))
		if seat == PLAYER_SEAT:
			if action_type == A.TRIBUTE:
				await _player_tribute(actions[0], gen)
			else:
				await _player_return(actions[0], gen)
		else:
			_ai_tribute_act(seat, action_type)
		return
	if gen == _generation:
		_set_status("进贡流程停滞（不应发生）")


func _player_tribute(desc: Dictionary, gen: int) -> void:
	var applied := false
	while not applied and gen == _generation and _rs.get_phase() == P.TRIBUTE:
		_tribute_panel.open_give(_rs.get_hand(PLAYER_SEAT), int(desc.get("min_count")),
			int(desc.get("max_count")), _tribute_total, _rs.get_level(), _rs.get_trump_suit())
		var cards: Array = await _tribute_panel.tribute_chosen
		_tribute_panel.hide_panel()
		if gen != _generation:
			return
		applied = _rs.apply_action(PLAYER_SEAT, {"type": A.TRIBUTE, "cards": cards})
		if applied:
			_set_status("你进贡 %d 张" % cards.size())
		else:
			_set_status("进贡被拒：须为手中最大的非分牌（§5）")


func _player_return(desc: Dictionary, gen: int) -> void:
	var to_seat := int(desc.get("to_seat"))
	var count := int(desc.get("count"))
	var applied := false
	while not applied and gen == _generation and _rs.get_phase() == P.TRIBUTE:
		_tribute_panel.open_return(_rs.get_hand(PLAYER_SEAT), SEAT_NAMES[to_seat], to_seat,
			count, _rs.get_level(), _rs.get_trump_suit())
		var res: Array = await _tribute_panel.return_chosen
		_tribute_panel.hide_panel()
		if gen != _generation:
			return
		applied = _rs.apply_action(PLAYER_SEAT,
			{"type": A.RETURN, "to_seat": int(res[0]), "cards": res[1]})
		if applied:
			_set_status("你还贡给 %s %d 张" % [SEAT_NAMES[to_seat], count])
		else:
			_set_status("还贡被拒：须为非分牌副牌（§5）")


func _ai_tribute_act(seat: int, action_type: int) -> void:
	var ai := _ais[seat] as HeuristicAI
	var action: Dictionary
	if action_type == A.TRIBUTE:
		action = ai.decide_tribute_give(_rs, seat)
	else:
		action = ai.decide_tribute_return(_rs, seat)
	if not _rs.apply_action(seat, action):
		_set_status("AI 进贡/还贡被拒（不应发生）")
		return
	if action_type == A.TRIBUTE:
		_set_status("%s 进贡 %d 张" % [SEAT_NAMES[seat], (action.get("cards") as Array).size()])
	else:
		_set_status("%s 还贡给 %s %d 张" % [SEAT_NAMES[seat],
			SEAT_NAMES[int(action.get("to_seat"))], (action.get("cards") as Array).size()])


# BOTTOM：扣底/扣王/捡补偿；玩家座弹对话框，AI 座自动并展示结果。
func _bottom_step(gen: int) -> void:
	for seat in RoundState.PLAYER_COUNT:
		var actions := _rs.get_available_actions(seat)
		if actions.is_empty():
			continue
		var action_type := int(actions[0].get("type"))
		if seat == PLAYER_SEAT:
			match action_type:
				A.DISCARD_BOTTOM:
					await _player_discard_bottom(gen)
				A.PICK_COMPENSATION:
					await _player_compensation(int(actions[0].get("count")), gen)
				_:
					# DISCARD_JOKERS 或仅 PASS（无王可扣时直接跳过，无需弹窗）
					if _has_action(actions, A.DISCARD_JOKERS):
						await _player_bottom_jokers(gen)
					elif _rs.apply_action(PLAYER_SEAT, {"type": A.PASS}):
						_set_status("你无王可扣，跳过")
		else:
			_ai_bottom_act(seat, action_type)
		return
	if gen == _generation:
		_set_status("扣底流程停滞（不应发生）")


func _has_action(actions: Array, action_type: int) -> bool:
	for action in actions:
		if int(action.get("type")) == action_type:
			return true
	return false


func _player_discard_bottom(gen: int) -> void:
	var applied := false
	while not applied and gen == _generation and _rs.get_phase() == P.BOTTOM:
		_bottom_panel.open_discard(_rs.get_hand(PLAYER_SEAT), _bottom_snapshot,
			_rs.get_level(), _rs.get_trump_suit())
		var cards: Array = await _bottom_panel.discard_chosen
		_bottom_panel.hide_panel()
		if gen != _generation:
			return
		applied = _rs.apply_action(PLAYER_SEAT, {"type": A.DISCARD_BOTTOM, "cards": cards})
		if applied:
			var msg := "你扣底 6 张"
			if _rs.is_bottom_public():
				msg += "，扣了王，底牌公开（§6.1）"
			if _rs.is_dry_pot():
				msg += "；干锅！底牌冻结，王奖励作废（§6.4）"
			_set_status(msg)
		else:
			_set_status("扣底被拒：须扣 6 张，且有大王须先扣大王（§6.2）")


func _player_bottom_jokers(gen: int) -> void:
	var decided := false
	while not decided and gen == _generation and _rs.get_phase() == P.BOTTOM:
		_bottom_panel.open_jokers(_rs.get_hand(PLAYER_SEAT), _rs.get_level(), _rs.get_trump_suit())
		var cards: Array = await _bottom_panel.jokers_decided
		_bottom_panel.hide_panel()
		if gen != _generation:
			return
		if cards.is_empty():
			decided = _rs.apply_action(PLAYER_SEAT, {"type": A.PASS})
			if decided:
				_set_status("你不扣王")
		else:
			decided = _rs.apply_action(PLAYER_SEAT, {"type": A.DISCARD_JOKERS, "cards": cards})
			if decided:
				_set_status("你扣王 %d 张，底牌公开（§6.3）" % cards.size())
			else:
				_set_status("扣王被拒：只能扣王，且有大王须先扣大王（§6.2）")


func _player_compensation(count: int, gen: int) -> void:
	var applied := false
	while not applied and gen == _generation and _rs.get_phase() == P.BOTTOM:
		_bottom_panel.open_compensation(_rs.get_bottom(), count, _rs.get_level(), _rs.get_trump_suit())
		var cards: Array = await _bottom_panel.compensation_chosen
		_bottom_panel.hide_panel()
		if gen != _generation:
			return
		applied = _rs.apply_action(PLAYER_SEAT, {"type": A.PICK_COMPENSATION, "cards": cards})
		if applied:
			var msg := "你捡补偿 %d 张" % count
			if _rs.is_dry_pot():
				msg += "；干锅！底牌冻结，王奖励作废（§6.4）"
			_set_status(msg)
		else:
			_set_status("捡牌被拒：须为底牌中最小的非分牌（§6.3）")


func _ai_bottom_act(seat: int, action_type: int) -> void:
	var ai := _ais[seat] as HeuristicAI
	var action: Dictionary
	if action_type == A.DISCARD_BOTTOM:
		action = ai.decide_bottom(_rs, seat)
	else:
		action = ai.decide_bottom_joker(_rs, seat)
	if not _rs.apply_action(seat, action):
		_set_status("AI 扣底/扣王被拒（不应发生）")
		return
	var msg := ""
	match action_type:
		A.DISCARD_BOTTOM:
			msg = "%s 扣底完成" % SEAT_NAMES[seat]
			if _rs.is_bottom_public():
				msg += "，扣了王，底牌公开"
		A.PICK_COMPENSATION:
			msg = "%s 捡补偿 %d 张" % [SEAT_NAMES[seat], (action.get("cards") as Array).size()]
		_:
			if int(action.get("type")) == A.DISCARD_JOKERS:
				msg = "%s 扣王 %d 张，底牌公开" % [SEAT_NAMES[seat], (action.get("cards") as Array).size()]
			else:
				msg = "%s 不扣王" % SEAT_NAMES[seat]
	if _rs.is_dry_pot():
		msg += "；干锅！底牌冻结，王奖励作废（§6.4）"
	_set_status(msg)


func _advance_play(gen: int) -> void:
	if gen != _generation:
		return
	if _rs.get_phase() != P.PLAYING:
		_show_settlement()
		return
	_refresh_all()
	var seat := _rs.get_current_seat()
	if seat == PLAYER_SEAT:
		_player_turn = true
		_set_status("轮到你出牌")
		_update_play_button()
		return  # 等待玩家点击“出牌”按钮
	_player_turn = false
	_update_play_button()
	_set_status("%s 思考中…" % SEAT_NAMES[seat])
	await get_tree().create_timer(_rng.randf_range(AI_THINK_MIN, AI_THINK_MAX)).timeout
	if gen != _generation:
		return
	var scores_before := [_rs.get_side_score(0), _rs.get_side_score(1)]
	var action: Dictionary = (_ais[seat] as HeuristicAI).decide_play(_rs, seat)
	var cards: Array[Card] = []
	cards.assign(action.get("cards", []))
	if not _rs.apply_action(seat, action):
		_set_status("AI 出牌被拒（不应发生）")
		return
	_broadcast_observe(seat, cards)
	await _after_play(seat, cards, gen, scores_before)
	_advance_play(gen)


func _after_play(seat: int, cards: Array[Card], gen: int, scores_before: Array) -> void:
	_show_trick_play(seat, cards)
	if seat == PLAYER_SEAT:
		_selected.clear()
		_refresh_hand()
	_refresh_seat_counts()
	_refresh_scores()
	var trick_done := _rs.get_phase() == P.SETTLEMENT or _rs.get_table_plays().is_empty()
	if trick_done:
		var winner := _rs.get_last_trick_winner()
		var gained: int = (_rs.get_side_score(0) - scores_before[0]) \
			+ (_rs.get_side_score(1) - scores_before[1])
		_set_status("%s 赢得本轮，收走 %d 分" % [SEAT_NAMES[winner], gained])
		await get_tree().create_timer(TRICK_COLLECT_DELAY).timeout
		if gen != _generation:
			return
		_clear_trick_views()


func _show_settlement() -> void:
	_player_turn = false
	_update_play_button()
	_bid_panel.hide_panel()
	_settlement_panel.show_result(_rs.get_result(), _round_prev_levels, SIDE_NAMES)


# 结算面板“下一局”（比赛未结束）：推进 MatchState 并自动存档，再开下一局；
# “新比赛”（比赛结束）：经 Game 重开整场比赛（覆盖存档，牌桌场景重进）。
func _on_settlement_continued() -> void:
	if _rs == null or _rs.get_phase() != P.SETTLEMENT:
		return
	var r := _rs.get_result()
	if r.is_empty():
		return
	if bool(r.get("match_over", false)):
		Game.new_match()
		return
	_apply_match_progress(r)
	_start_round(Game.next_round_config())


# 结算面板“回主菜单”（比赛结束）：先落档（比赛结束会清除存档），再回主菜单。
func _on_settlement_menu() -> void:
	if _rs != null and _rs.get_phase() == P.SETTLEMENT:
		var r := _rs.get_result()
		if not r.is_empty():
			_apply_match_progress(r)
	Game.quit_to_menu()


func _apply_match_progress(result: Dictionary) -> void:
	if _match_progress_applied:
		return
	_match_progress_applied = true
	Game.finish_round(result)


# “退出比赛”二次确认：3 秒内再点一次才退出（放弃当前局，从最近局结算点恢复）。
func _on_exit_pressed() -> void:
	if not _exit_armed:
		_exit_armed = true
		_exit_button.text = "确认退出？"
		await get_tree().create_timer(3.0).timeout
		_exit_armed = false
		if is_instance_valid(_exit_button):
			_exit_button.text = "退出比赛"
		return
	Game.quit_to_menu()


# --- 玩家交互 ---

func _on_bid_chosen(action: Dictionary) -> void:
	if _rs == null:
		return
	var phase := _rs.get_phase()
	if phase != P.DEALING and phase != P.BIDDING:
		return
	if not _rs.apply_action(PLAYER_SEAT, action):
		_set_status("该叫价已无效")
		_refresh_bid_panel()
		return
	_last_bid_text = "你 %s" % BidPanel.bid_text(int(action.get("kind")),
		int(action.get("suit", -1)), _rs.get_level())
	_set_status(_last_bid_text)
	_bid_time_left = BIDDING_SECONDS  # 规则 §4.3：每次亮/反重置倒计时
	_ai_bid_pending = true
	_refresh_bid_panel()


func _on_card_clicked(view: CardView) -> void:
	if not _player_turn or _rs.get_phase() != P.PLAYING:
		return
	if _selected.has(view):
		_selected.erase(view)
		view.set_selected(false)
	else:
		_selected.append(view)
		view.set_selected(true)
	_layout_hand()
	_update_play_button()


func _on_play_pressed() -> void:
	if not _player_turn or _rs.get_phase() != P.PLAYING:
		return
	var gen := _generation
	var scores_before := [_rs.get_side_score(0), _rs.get_side_score(1)]
	var cards: Array[Card] = []
	for view in _selected:
		cards.append(view.card)
	if not _rs.apply_action(PLAYER_SEAT, {"type": A.PLAY, "cards": cards}):
		_set_status("不符合规则：牌型须为单张/棒子/滚子，跟牌须跟同花色")
		return
	_player_turn = false
	_update_play_button()
	_broadcast_observe(PLAYER_SEAT, cards)
	await _after_play(PLAYER_SEAT, cards, gen, scores_before)
	_advance_play(gen)


func _update_play_button() -> void:
	var counts := _allowed_play_counts()
	_play_button.disabled = not (_player_turn and counts.has(_selected.size()))
	if not _player_turn:
		_hint_label.text = ""
	elif counts.size() > 1:
		_hint_label.text = "领出：选 1~3 张（单张/棒子/滚子），已选 %d 张" % _selected.size()
	elif counts.size() == 1:
		_hint_label.text = "跟牌：需出 %d 张，已选 %d 张" % [counts[0], _selected.size()]


func _allowed_play_counts() -> Array[int]:
	var counts: Array[int] = []
	if _rs == null or _rs.get_phase() != P.PLAYING:
		return counts
	for action in _rs.get_available_actions(PLAYER_SEAT):
		if action.get("type") == A.PLAY:
			counts.append(action.get("count"))
	return counts


func _broadcast_observe(seat: int, cards: Array[Card]) -> void:
	for ai in _ais.values():
		(ai as HeuristicAI).observe_play(seat, cards)


# --- 视图刷新与动画 ---

func _refresh_all() -> void:
	_refresh_hand()
	_refresh_seat_counts()
	_refresh_scores()
	_refresh_bottom()


func _refresh_bid_panel() -> void:
	if _rs == null:
		return
	var phase := _rs.get_phase()
	if phase != P.DEALING and phase != P.BIDDING:
		_bid_panel.hide_panel()
		return
	var bids: Array = []
	for action in _rs.get_available_actions(PLAYER_SEAT):
		if int(action.get("type")) == A.BID:
			bids.append(action)
	_bid_panel.set_bids(bids, _rs.get_level())
	if _last_bid_text.is_empty():
		_bid_panel.set_current_text("当前最高：无")
	else:
		_bid_panel.set_current_text("当前最高：%s" % _last_bid_text)
	if phase == P.DEALING:
		_bid_panel.set_countdown_text("发牌中：可随时抢亮/反")


func _refresh_hand() -> void:
	for view in _hand_views:
		view.queue_free()
	_hand_views.clear()
	_selected.clear()
	var hand := _rs.get_hand(PLAYER_SEAT)
	hand.sort_custom(_compare_cards)  # 仅展示排序：副牌按花色分组，主牌列右侧
	for card in hand:
		var view := CardView.create(card, true,
			Play.is_trump(card, _rs.get_level(), _rs.get_trump_suit()))
		view.clicked.connect(_on_card_clicked)
		_hand_area.add_child(view)
		_hand_views.append(view)
	_layout_hand()


func _compare_cards(a: Card, b: Card) -> bool:
	var ta := Play.is_trump(a, _rs.get_level(), _rs.get_trump_suit())
	var tb := Play.is_trump(b, _rs.get_level(), _rs.get_trump_suit())
	if ta != tb:
		return not ta
	if not ta:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.rank > b.rank
	return Play.power(a, _rs.get_level(), _rs.get_trump_suit()) \
		< Play.power(b, _rs.get_level(), _rs.get_trump_suit())


func _layout_hand() -> void:
	var n := _hand_views.size()
	if n == 0:
		return
	var spacing: float = minf(CardView.DEFAULT_SIZE.x + 6.0,
		(HAND_WIDTH - CardView.DEFAULT_SIZE.x) / float(maxi(1, n - 1)))
	var start_x := -((n - 1) * spacing + CardView.DEFAULT_SIZE.x) / 2.0
	for i in n:
		var view := _hand_views[i]
		view.position = Vector2(start_x + i * spacing, -SELECT_LIFT if view.selected else 0.0)


func _refresh_seat_counts() -> void:
	for seat in RoundState.PLAYER_COUNT:
		var marker := "（庄）" if seat == _rs.get_dealer_seat() else ""
		_seat_labels[seat].text = SEAT_NAMES[seat] + marker
		_count_labels[seat].text = "" if seat == PLAYER_SEAT else "%d 张" % _rs.get_hand(seat).size()


func _refresh_scores() -> void:
	var trump := "未定"
	var suit: int = _rs.get_trump_suit()
	if suit >= 0 and suit < CardView.SUIT_SYMBOLS.size():
		trump = CardView.SUIT_SYMBOLS[suit]
	_score_label.text = "级别 %d　主花色 %s\n我方（南北）%d 分　对方（东西）%d 分" % [
		_rs.get_level(), trump, _rs.get_side_score(0), _rs.get_side_score(1)]


func _refresh_bottom() -> void:
	for view in _bottom_views:
		if is_instance_valid(view):
			view.queue_free()
	_bottom_views.clear()
	var bottom := _rs.get_bottom()
	var text := "底牌：%d 张" % bottom.size()
	if _rs.is_bottom_public():
		text += "（公开）"
	if _rs.is_dry_pot():
		text += "（干锅）"
	_bottom_label.text = text
	if _rs.is_bottom_public() and not bottom.is_empty():
		var small := Vector2(40, 55)
		for i in bottom.size():
			var view := CardView.create(bottom[i], true,
				Play.is_trump(bottom[i], _rs.get_level(), _rs.get_trump_suit()), small)
			view.position = Vector2(20, 112) + Vector2(i * (small.x + 4), 0)
			view.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(view)
			_bottom_views.append(view)


func _set_status(text: String) -> void:
	_status_label.text = text


func _animate_deal(seat: int) -> void:
	var view := CardView.create(null, false)
	view.mouse_filter = MOUSE_FILTER_IGNORE
	view.position = DECK_POS - CardView.DEFAULT_SIZE / 2
	_fx_layer.add_child(view)
	var tween := create_tween()
	tween.tween_property(view, "position",
		SEAT_ANCHORS[seat] - CardView.DEFAULT_SIZE / 2, DEAL_INTERVAL * 0.6)
	tween.tween_callback(view.queue_free)


func _show_trick_play(seat: int, cards: Array[Card]) -> void:
	var views: Array[CardView] = []
	var step := CardView.DEFAULT_SIZE.x + 6.0
	var total_w := cards.size() * step - 6.0
	for i in cards.size():
		var view := CardView.create(cards[i], true,
			Play.is_trump(cards[i], _rs.get_level(), _rs.get_trump_suit()))
		view.mouse_filter = MOUSE_FILTER_IGNORE
		view.position = SEAT_ANCHORS[seat] - CardView.DEFAULT_SIZE / 2
		_center_layer.add_child(view)
		var target: Vector2 = TRICK_SLOTS[seat] + Vector2(i * step - total_w / 2.0, -CardView.DEFAULT_SIZE.y / 2.0)
		create_tween().tween_property(view, "position", target, PLAY_TWEEN_TIME)
		views.append(view)
	_trick_views[seat] = views


func _clear_trick_views() -> void:
	for views in _trick_views:
		for view in views:
			if is_instance_valid(view):
				view.queue_free()
	_trick_views.clear()
	for i in RoundState.PLAYER_COUNT:
		_trick_views.append([])
