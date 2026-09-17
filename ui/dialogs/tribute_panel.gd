class_name TributePanel
extends ModalPanel
## 进贡/还贡面板（规则 §5）。
## 进贡：每张贡牌必须是手中最大的非分牌，玩家只决定贡几张（预览 = 与 Tribute.can_tribute 同口径预选）。
## 还贡：庄家对每位贡手分别返还等量非分副牌；可选牌由 core 查询限定（非分且非主），张数来自 RETURN 描述符。

signal tribute_chosen(cards: Array)
signal return_chosen(to_seat: int, cards: Array)

enum Mode { NONE, GIVE, RETURN }

const CARD_SIZE := Vector2(48, 66)

var _mode: int = Mode.NONE
var _hand: Array[Card] = []
var _level := 0
var _trump := -1
var _count := 0
var _to_seat := -1
var _need := 0
var _preview_row: HFlowContainer = null
var _selected: Array[CardView] = []
var _confirm_button: Button = null


## 贡牌预选：手中牌力最大的 count 张非分牌（与 Tribute.can_tribute 同口径，必然合法）。
static func suggest_tribute(hand: Array[Card], count: int, level: int, trump: int) -> Array[Card]:
	var candidates: Array[Card] = []
	for card in hand:
		if card.score_value() == 0:
			candidates.append(card)
	candidates.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) > Play.power(b, level, trump))
	var picked: Array[Card] = []
	picked.assign(candidates.slice(0, count))
	return picked


func get_mode() -> int:
	return _mode


## 进贡模式：min_count/max_count 来自 TRIBUTE 描述符，total 为本局合计贡牌张数。
func open_give(hand: Array[Card], min_count: int, max_count: int, total: int,
		level: int, trump: int) -> void:
	_reset("进贡")
	_mode = Mode.GIVE
	_hand = hand
	_level = level
	_trump = trump
	_add_info("抓分方本局须合计进贡 %d 张，由你与队友分摊（§5）。\n贡牌必须是手中最大的非分牌，请选择你贡几张：" % total)
	var top := mini(max_count, suggest_tribute(hand, max_count, level, trump).size())
	var bottom := mini(min_count, top)
	_count = bottom
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	_content.add_child(row)
	for n in range(bottom, top + 1):
		var button := Button.new()
		button.text = "贡 %d 张" % n
		button.pressed.connect(_set_count.bind(n))
		row.add_child(button)
	_preview_row = HFlowContainer.new()
	_preview_row.add_theme_constant_override("h_separation", 6)
	_content.add_child(_preview_row)
	_confirm_button = Button.new()
	_confirm_button.text = "确定进贡"
	_confirm_button.pressed.connect(_on_give_confirmed)
	_content.add_child(_confirm_button)
	_refresh_preview()


## 还贡模式（玩家是庄家）：向 to_seat 返还 count 张非分副牌。
func open_return(hand: Array[Card], to_name: String, to_seat: int, count: int,
		level: int, trump: int) -> void:
	_reset("还贡")
	_mode = Mode.RETURN
	_hand = hand
	_level = level
	_trump = trump
	_to_seat = to_seat
	_need = count
	_selected.clear()
	_add_info("还贡给 %s：选择 %d 张非分牌副牌（不能还分牌或主牌，§5）。" % [to_name, count])
	var sorted: Array[Card] = hand.duplicate()
	sorted.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) < Play.power(b, level, trump))
	for view in _add_card_grid(sorted, level, trump, CARD_SIZE):
		if _is_returnable(view.card):
			view.clicked.connect(_on_return_card_clicked)
		else:
			view.modulate = Color(0.45, 0.45, 0.45)
			view.mouse_filter = MOUSE_FILTER_IGNORE
	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_on_return_confirmed)
	_content.add_child(_confirm_button)
	_update_return_confirm()


func _set_count(n: int) -> void:
	_count = n
	_refresh_preview()


func _refresh_preview() -> void:
	for child in _preview_row.get_children():
		child.queue_free()
	if _count == 0:
		var label := Label.new()
		label.text = "（你不贡，由队友补足）"
		_preview_row.add_child(label)
		return
	for card in suggest_tribute(_hand, _count, _level, _trump):
		var view := CardView.create(card, true, Play.is_trump(card, _level, _trump), CARD_SIZE)
		view.mouse_filter = MOUSE_FILTER_IGNORE
		_preview_row.add_child(view)


func _on_give_confirmed() -> void:
	tribute_chosen.emit(suggest_tribute(_hand, _count, _level, _trump))


func _is_returnable(card: Card) -> bool:
	# 规则 §5 还贡：非分牌副牌；与 Tribute.can_return 同口径，apply_action 终判
	return card.score_value() == 0 and not Play.is_trump(card, _level, _trump)


func _on_return_card_clicked(view: CardView) -> void:
	if _selected.has(view):
		_selected.erase(view)
		view.set_selected(false)
	elif _selected.size() < _need:
		_selected.append(view)
		view.set_selected(true)
	_update_return_confirm()


func _update_return_confirm() -> void:
	_confirm_button.disabled = _selected.size() != _need
	_confirm_button.text = "确定还贡（已选 %d/%d）" % [_selected.size(), _need]


func _on_return_confirmed() -> void:
	var cards: Array[Card] = []
	for view in _selected:
		cards.append(view.card)
	return_chosen.emit(_to_seat, cards)
