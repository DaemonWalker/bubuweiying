class_name BidPanel
extends PanelContainer
## 亮主/反主面板（规则 §4）：发牌中与定主倒计时内，按 core 枚举的合法叫价列出按钮。
## 点击发出 bid_chosen(action)；合法性由 RoundState.apply_action 终判。
## 倒计时文本由 table 驱动（规则 §4.3：默认 5 秒，每次亮/反重置，超时调 close_bidding()）。

signal bid_chosen(action: Dictionary)

var _current_label: Label
var _countdown_label: Label
var _buttons_box: VBoxContainer
var _actions: Array = []


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.11, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var title := Label.new()
	title.text = "亮主 / 反主"
	vbox.add_child(title)
	_current_label = Label.new()
	_current_label.text = "当前最高：无"
	vbox.add_child(_current_label)
	_countdown_label = Label.new()
	vbox.add_child(_countdown_label)
	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_buttons_box)
	visible = false


## 叫价的展示文本（含首局抢亮大王与王亮定主花色）。
static func bid_text(kind: int, suit: int, level: int) -> String:
	var suit_text := ""
	if suit >= 0 and suit < CardView.SUIT_SYMBOLS.size():
		suit_text = CardView.SUIT_SYMBOLS[suit]
	match kind:
		Bidding.Kind.FIRST_ROUND_JOKER:
			return "抢亮大王！"
		Bidding.Kind.LEVEL_1:
			return "亮 %s%d" % [suit_text, level]
		Bidding.Kind.LEVEL_2:
			return "反 %s%d×2" % [suit_text, level]
		Bidding.Kind.LEVEL_3:
			return "反 %s%d×3" % [suit_text, level]
		Bidding.Kind.SMALL_JOKERS_3:
			return "小王×3 定 %s主" % suit_text
		Bidding.Kind.BIG_JOKERS_3:
			return "大王×3 定 %s主" % suit_text
	return "叫价"


## 刷新合法叫价按钮（actions 为 get_available_actions 中的 BID 描述符）；空则隐藏面板。
func set_bids(actions: Array, level: int) -> void:
	_actions = actions.duplicate()
	for child in _buttons_box.get_children():
		child.queue_free()
	for action in _actions:
		var button := Button.new()
		button.text = bid_text(int(action.get("kind")), int(action.get("suit", -1)), level)
		button.pressed.connect(_on_button_pressed.bind(action))
		_buttons_box.add_child(button)
	visible = not _actions.is_empty()


func set_countdown_text(text: String) -> void:
	_countdown_label.text = text


func set_current_text(text: String) -> void:
	_current_label.text = text


func hide_panel() -> void:
	visible = false
	_actions.clear()


## 当前展示的合法叫价（测试/冒烟驱动用）。
func get_bid_actions() -> Array:
	return _actions.duplicate()


func _on_button_pressed(action: Dictionary) -> void:
	bid_chosen.emit(action.duplicate())
