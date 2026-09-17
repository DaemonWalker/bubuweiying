class_name BottomPanel
extends ModalPanel
## 扣底/扣王/捡补偿面板（规则 §6）。
## 扣底：庄家从 45 张手牌中选 6 张扣回（底牌来源标“底”）；扣王有大王须先扣大王（§6.2，core 终判）。
## 其他家扣王：只展示手中的王，小王须在所有大王选中后才可选；跳过即 PASS。
## 捡补偿：扣王后从公开底牌中选等量最小非分牌（§6.3），合法性由 apply_action 终判。

signal discard_chosen(cards: Array)
signal jokers_decided(cards: Array)
signal compensation_chosen(cards: Array)

enum Mode { NONE, DISCARD, JOKERS, COMPENSATION }

const GRID_CARD_SIZE := Vector2(46, 64)

var _mode: int = Mode.NONE
var _selected: Array[CardView] = []
var _target := 0
var _level := 0
var _trump := -1
var _confirm_button: Button = null
var _confirm_label := ""
var _big_views: Array[CardView] = []
var _small_views: Array[CardView] = []


func get_mode() -> int:
	return _mode


## 庄家扣底：hand 为含底牌的 45 张手牌，bottom_snapshot 标出底牌来源。
func open_discard(hand: Array[Card], bottom_snapshot: Array[Card], level: int, trump: int) -> void:
	_reset("扣底")
	_mode = Mode.DISCARD
	_level = level
	_trump = trump
	_target = Deck.BOTTOM_SIZE
	_selected.clear()
	_add_info("你已拿起 6 张底牌（标“底”）。选择要扣回的 6 张牌；若要扣王，有大王须先扣大王（§6.2）。")
	var sorted: Array[Card] = hand.duplicate()
	sorted.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) < Play.power(b, level, trump))
	var views := _add_card_grid(sorted, level, trump, GRID_CARD_SIZE, 940.0, 300.0)
	var marks: Array[bool] = []
	marks.resize(views.size())
	marks.fill(false)
	for snap in bottom_snapshot:
		for i in views.size():
			if not marks[i] and views[i].card.is_identical(snap):
				marks[i] = true
				var tag := Label.new()
				tag.text = "底"
				tag.position = Vector2(GRID_CARD_SIZE.x - 16, GRID_CARD_SIZE.y - 20)
				tag.add_theme_color_override("font_color", Color(0.95, 0.55, 0.1))
				views[i].add_child(tag)
				break
	for view in views:
		view.clicked.connect(_on_grid_card_clicked)
	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_on_discard_confirmed)
	_content.add_child(_confirm_button)
	_update_confirm("扣回底牌")


## 其他三家扣王：展示手中的王（大王在前），可不扣（PASS）。
func open_jokers(hand: Array[Card], level: int, trump: int) -> void:
	_reset("扣王")
	_mode = Mode.JOKERS
	_level = level
	_trump = trump
	_target = 0
	_selected.clear()
	_big_views.clear()
	_small_views.clear()
	_add_info("可将王扣入底牌（底牌随之公开），之后从底牌捡等量最小非分牌作补偿（§6.3）。\n有大王须先扣大王（§6.2）。")
	var jokers: Array[Card] = []
	for card in hand:
		if card.is_big_joker():
			jokers.append(card)
	for card in hand:
		if card.is_small_joker():
			jokers.append(card)
	for view in _add_card_grid(jokers, level, trump, GRID_CARD_SIZE, 940.0, 130.0):
		view.clicked.connect(_on_joker_clicked)
		if view.card.is_big_joker():
			_big_views.append(view)
		else:
			_small_views.append(view)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	_content.add_child(row)
	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_on_jokers_confirmed)
	row.add_child(_confirm_button)
	var pass_button := Button.new()
	pass_button.text = "不扣王"
	pass_button.pressed.connect(func() -> void: jokers_decided.emit([]))
	row.add_child(pass_button)
	_refresh_joker_states()


## 扣王后捡补偿：bottom 为公开底牌，count 来自 PICK_COMPENSATION 描述符。
func open_compensation(bottom: Array[Card], count: int, level: int, trump: int) -> void:
	_reset("捡补偿牌")
	_mode = Mode.COMPENSATION
	_level = level
	_trump = trump
	_target = count
	_selected.clear()
	_add_info("从公开底牌中捡 %d 张最小的非分牌（不能捡分牌，§6.3）。" % count)
	var sorted: Array[Card] = bottom.duplicate()
	sorted.sort_custom(func(a: Card, b: Card) -> bool:
		return Play.power(a, level, trump) < Play.power(b, level, trump))
	for view in _add_card_grid(sorted, level, trump, GRID_CARD_SIZE, 940.0, 150.0):
		if view.card.score_value() == 0:
			view.clicked.connect(_on_grid_card_clicked)
		else:
			view.modulate = Color(0.45, 0.45, 0.45)
			view.mouse_filter = MOUSE_FILTER_IGNORE
	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_on_compensation_confirmed)
	_content.add_child(_confirm_button)
	_update_confirm("捡补偿牌")


func _on_grid_card_clicked(view: CardView) -> void:
	if _selected.has(view):
		_selected.erase(view)
		view.set_selected(false)
	elif _selected.size() < _target:
		_selected.append(view)
		view.set_selected(true)
	_update_confirm(_confirm_label)


func _update_confirm(label: String) -> void:
	_confirm_label = label
	_confirm_button.disabled = _selected.size() != _target
	_confirm_button.text = "%s（已选 %d/%d）" % [label, _selected.size(), _target]


func _selected_cards() -> Array[Card]:
	var cards: Array[Card] = []
	for view in _selected:
		cards.append(view.card)
	return cards


func _on_discard_confirmed() -> void:
	discard_chosen.emit(_selected_cards())


func _on_compensation_confirmed() -> void:
	compensation_chosen.emit(_selected_cards())


func _on_joker_clicked(view: CardView) -> void:
	if _selected.has(view):
		_selected.erase(view)
		view.set_selected(false)
		if view.card.is_big_joker():
			# 规则 §6.2：取消大王时，已选小王须一并取消（先大王后小王）
			for small in _small_views:
				if _selected.has(small):
					_selected.erase(small)
					small.set_selected(false)
	else:
		_selected.append(view)
		view.set_selected(true)
	_refresh_joker_states()


func _refresh_joker_states() -> void:
	var all_big_selected := true
	for view in _big_views:
		if not _selected.has(view):
			all_big_selected = false
	for view in _small_views:
		var allowed := all_big_selected or _selected.has(view)
		view.mouse_filter = MOUSE_FILTER_STOP if allowed else MOUSE_FILTER_IGNORE
		view.modulate = Color.WHITE if allowed else Color(0.45, 0.45, 0.45)
	_confirm_button.disabled = _selected.is_empty()
	_confirm_button.text = "扣王（已选 %d 张）" % _selected.size()


func _on_jokers_confirmed() -> void:
	jokers_decided.emit(_selected_cards())
