class_name CardView
extends Control
## 单张牌的可视化：代码绘制（圆角矩形底 + 花色符号 + 点数），不依赖美术素材。
## 主牌金色边框，选中蓝色加粗边框（上移由外部布局负责），悬停提亮。
## face_up = false 时绘制牌背（card 可为 null）。点击发出 clicked 信号。

signal clicked(view: CardView)

const DEFAULT_SIZE := Vector2(64, 88)
const SUIT_SYMBOLS := ["♠", "♥", "♣", "♦"]
const RANK_LABELS := {11: "J", 12: "Q", 13: "K", 14: "A"}
const FACE_COLOR := Color(0.96, 0.95, 0.9)
const BACK_COLOR := Color(0.18, 0.32, 0.55)
const BORDER_COLOR := Color(0.35, 0.3, 0.25)
const TRUMP_BORDER := Color(1.0, 0.8, 0.2)
const SELECT_BORDER := Color(0.3, 0.7, 1.0)
const RED := Color(0.8, 0.12, 0.12)
const BLACK := Color(0.12, 0.12, 0.12)

var card: Card = null
var face_up := true
var is_trump := false
var selected := false

var _hovered := false


static func create(p_card: Card, p_face_up := true, p_is_trump := false,
		p_size := DEFAULT_SIZE) -> CardView:
	var view := CardView.new()
	view.card = p_card
	view.face_up = p_face_up
	view.is_trump = p_is_trump
	view.custom_minimum_size = p_size
	view.size = p_size
	return view


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(self)
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(size.x * 0.09))
	if not face_up:
		style.bg_color = BACK_COLOR
		style.set_border_width_all(1)
		style.border_color = Color(0.6, 0.7, 0.9, 0.6)
		draw_style_box(style, rect)
		draw_rect(rect.grow(-5), Color(1, 1, 1, 0.12), false, 1.0)
		return
	style.bg_color = FACE_COLOR.lightened(0.08) if _hovered else FACE_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	if is_trump:
		style.border_color = TRUMP_BORDER
		style.set_border_width_all(2)
	if selected:
		style.border_color = SELECT_BORDER
		style.set_border_width_all(3)
	draw_style_box(style, rect)
	if card == null:
		return
	var font := get_theme_default_font()
	var color := _card_color()
	if card.is_joker():
		var text := "大王" if card.is_big_joker() else "小王"
		var fs := int(size.x * 0.26)
		draw_string(font, Vector2(6, size.y * 0.4), text.substr(0, 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_string(font, Vector2(6, size.y * 0.4 + fs * 1.2), text.substr(1, 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		return
	var rank_text: String = RANK_LABELS.get(card.rank, str(card.rank))
	var rank_size := int(size.x * 0.34)
	draw_string(font, Vector2(5, rank_size + 3), rank_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, color)
	draw_string(font, Vector2(0, size.y * 0.82), SUIT_SYMBOLS[card.suit],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.44), color)


func _card_color() -> Color:
	if card.is_big_joker():
		return RED
	if card.suit == Card.Suit.HEART or card.suit == Card.Suit.DIAMOND:
		return RED
	return BLACK
