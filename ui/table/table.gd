extends Control
## 牌桌场景（step-05）：四家牌局可视化 + 玩家出牌交互，走通 PLAYING 阶段人机闭环。
## 亮主/进贡/扣底 UI 属 step-06，本阶段由 HeuristicAI 对全部座位自动完成（含玩家座）。
## 规则判断只经 RoundState.get_available_actions / apply_action，UI 层不做任何合法性判断。

const A := RoundState.ActionType
const P := RoundState.Phase
const PLAYER_SEAT := 0
const SEAT_NAMES := ["南（你）", "西", "北（队友）", "东"]
const DEAL_INTERVAL := 0.5  # 规则 §4.1：发牌动画约 1 秒 2 张
const AI_THINK_MIN := 0.5
const AI_THINK_MAX := 1.0
const AUTO_STEP_DELAY := 0.4
const TRICK_COLLECT_DELAY := 0.9
const PLAY_TWEEN_TIME := 0.25
const HAND_WIDTH := 1200.0
const SELECT_LIFT := 16.0
const SEAT_ANCHORS := [Vector2(800, 800), Vector2(110, 450), Vector2(800, 90), Vector2(1490, 450)]
const TRICK_SLOTS := [Vector2(800, 580), Vector2(560, 430), Vector2(800, 290), Vector2(1040, 430)]
const DECK_POS := Vector2(800, 450)
const BRANCH_TEXTS := {
	1: "抓分方 0 分：庄家方赢得整场比赛！",
	2: "抓分方 300 分：抓分方赢得整场比赛！",
	3: "抠出底牌 3 大王：抓分方赢得整场比赛！",
	4: "抓分方上台，底牌王追加升级",
	5: "抓分方上台，不升级",
	6: "庄家连任，双方不升级",
	7: "庄家方升 1 级，底牌王追加升级",
}

var _rs: RoundState = null
var _ais: Array[HeuristicAI] = []
var _rng := RandomNumberGenerator.new()
var _generation := 0  # 重开一局时使未完成的 await 失效

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
var _result_label: Label
var _play_button: Button
var _restart_button: Button
var _seat_labels: Array[Label] = []
var _count_labels: Array[Label] = []


func _ready() -> void:
	_rng.randomize()
	_build_ui()
	_start_round()


func _start_round() -> void:
	_generation += 1
	_rs = RoundState.new({"is_first_round": true, "seed": _rng.randi()})
	_ais.clear()
	for seat in RoundState.PLAYER_COUNT:
		var ai := HeuristicAI.new()
		ai.start_round(_rs, seat)
		_ais.append(ai)
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
	_result_label.visible = false
	_restart_button.visible = false
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
	_result_label = _make_label(Vector2(500, 320), Vector2(600, 220), HORIZONTAL_ALIGNMENT_CENTER)
	_result_label.add_theme_font_size_override("font_size", 22)
	_result_label.visible = false
	_play_button = Button.new()
	_play_button.text = "出牌"
	_play_button.position = Vector2(1430, 770)
	_play_button.size = Vector2(140, 48)
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play_pressed)
	add_child(_play_button)
	_restart_button = Button.new()
	_restart_button.text = "再来一局"
	_restart_button.position = Vector2(730, 560)
	_restart_button.size = Vector2(140, 44)
	_restart_button.visible = false
	_restart_button.pressed.connect(_start_round)
	add_child(_restart_button)
	var label_pos := [Vector2(1150, 856), Vector2(50, 380), Vector2(725, 16), Vector2(1430, 380)]
	for seat in RoundState.PLAYER_COUNT:
		_seat_labels.append(_make_label(label_pos[seat], Vector2(160, 26), HORIZONTAL_ALIGNMENT_CENTER))
		_count_labels.append(_make_label(label_pos[seat] + Vector2(0, 26), Vector2(160, 24),
			HORIZONTAL_ALIGNMENT_CENTER))
		_seat_labels[seat].text = SEAT_NAMES[seat]
	for i in RoundState.PLAYER_COUNT:
		_trick_views.append([])


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
		for s in RoundState.PLAYER_COUNT:
			var bid := _ais[s].decide_bid(_rs, s)
			if not bid.is_empty() and _rs.apply_action(s, bid):
				_set_status("%s 亮主！" % SEAT_NAMES[s])
		if seat == PLAYER_SEAT:
			_refresh_hand()
		_refresh_seat_counts()
		await get_tree().create_timer(DEAL_INTERVAL).timeout
	if gen != _generation:
		return
	_refresh_all()
	_auto_pre_play(gen)


# 亮主/进贡/扣底本阶段无 UI，全部交给 AI 自动完成（step-06 替换为玩家交互）。
func _auto_pre_play(gen: int) -> void:
	while gen == _generation:
		var phase: int = _rs.get_phase()
		if phase == P.BIDDING:
			_set_status("亮主/反主中…（自动）")
			var any_bid := false
			for seat in RoundState.PLAYER_COUNT:
				var bid := _ais[seat].decide_bid(_rs, seat)
				if not bid.is_empty() and _rs.apply_action(seat, bid):
					any_bid = true
					_set_status("%s 叫价" % SEAT_NAMES[seat])
			if not any_bid:
				_rs.close_bidding()
		elif phase == P.TRIBUTE or phase == P.BOTTOM:
			_set_status("进贡/扣底中…（自动）")
			if not _auto_act_one():
				_set_status("自动流程停滞（不应发生）")
				return
		else:
			break
		_refresh_all()
		await get_tree().create_timer(AUTO_STEP_DELAY).timeout
	if gen != _generation:
		return
	_refresh_all()
	if _rs.get_phase() == P.PLAYING:
		_advance_play(gen)


# TRIBUTE / BOTTOM：找到当前有动作的座位，按动作类型路由到对应 decide_*（同 test_ai_match）。
func _auto_act_one() -> bool:
	for seat in RoundState.PLAYER_COUNT:
		var actions := _rs.get_available_actions(seat)
		if actions.is_empty():
			continue
		var action: Dictionary
		match int(actions[0].get("type")):
			A.TRIBUTE:
				action = _ais[seat].decide_tribute_give(_rs, seat)
			A.RETURN:
				action = _ais[seat].decide_tribute_return(_rs, seat)
			A.DISCARD_BOTTOM:
				action = _ais[seat].decide_bottom(_rs, seat)
			_:
				action = _ais[seat].decide_bottom_joker(_rs, seat)
		return _rs.apply_action(seat, action)
	return false


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
	var action := _ais[seat].decide_play(_rs, seat)
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
	var r := _rs.get_result()
	var lines := PackedStringArray()
	lines.append("—— 一局结束 ——")
	lines.append("抓分方总分 S = %d（%s）" % [r.get("catcher_score", 0),
		"抠底，底牌分翻倍" if r.get("kongdi", false) else "保底"])
	lines.append(BRANCH_TEXTS.get(r.get("branch", 0), ""))
	lines.append("庄家方级别 %d　抓分方级别 %d" % [r.get("dealer_level", 0), r.get("catcher_level", 0)])
	_result_label.text = "\n".join(lines)
	_result_label.visible = true
	_restart_button.visible = true


# --- 玩家交互 ---

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
	for ai in _ais:
		ai.observe_play(seat, cards)


# --- 视图刷新与动画 ---

func _refresh_all() -> void:
	_refresh_hand()
	_refresh_seat_counts()
	_refresh_scores()
	_refresh_bottom()


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
