class_name CardView
extends Control
## 单张牌的可视化：牌面使用 Vector Playing Cards 贴图（assets/cards/，公有领域）。
## 主牌金色边框 + 右上角“主”字徽章，选中蓝色加粗边框，悬停提亮。
## face_up = false 时绘制牌背（card 可为 null）。点击发出 clicked 信号。

signal clicked(view: CardView)

const DEFAULT_SIZE := Vector2(64, 88)
const SUIT_SYMBOLS := ["♠", "♥", "♣", "♦"]
const RANK_LABELS := {11: "J", 12: "Q", 13: "K", 14: "A"}
const SUIT_NAMES := ["spades", "hearts", "clubs", "diamonds"]
const CARD_DIR := "res://assets/cards/"
const TRUMP_BORDER := Color(1.0, 0.8, 0.2)
const SELECT_BORDER := Color(0.3, 0.7, 1.0)

static var _texture_cache: Dictionary = {}

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


## 牌面对应的贴图：大王=红 Joker，小王=黑 Joker；card 为 null 时用空牌占位。
static func face_texture(p_card: Card) -> Texture2D:
	if p_card == null:
		return _texture("card_empty")
	if p_card.is_big_joker():
		return _texture("card_joker_red")
	if p_card.is_small_joker():
		return _texture("card_joker_black")
	var rank_text: String = RANK_LABELS.get(p_card.rank, "%02d" % p_card.rank)
	return _texture("card_%s_%s" % [SUIT_NAMES[p_card.suit], rank_text])


static func _texture(texture_name: String) -> Texture2D:
	if not _texture_cache.has(texture_name):
		_texture_cache[texture_name] = load(CARD_DIR + texture_name + ".png")
	return _texture_cache[texture_name]


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
	if not face_up:
		draw_texture_rect(_texture("card_back"), rect, false)
		return
	draw_texture_rect(face_texture(card), rect, false)
	if _hovered:
		var overlay := StyleBoxFlat.new()
		overlay.bg_color = Color(1, 1, 1, 0.15)
		overlay.set_corner_radius_all(int(size.x * 0.09))
		draw_style_box(overlay, rect)
	if is_trump:
		_draw_border(rect, TRUMP_BORDER, 2)
	if selected:
		_draw_border(rect, SELECT_BORDER, 3)
	if is_trump:
		_draw_trump_badge(get_theme_default_font())


func _draw_border(rect: Rect2, color: Color, width: int) -> void:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_corner_radius_all(int(size.x * 0.09))
	style.border_color = color
	style.set_border_width_all(width)
	draw_style_box(style, rect)


# 右上角金色圆形“主”字徽章（主牌一眼可辨）。
func _draw_trump_badge(font: Font) -> void:
	var r := size.x * 0.17
	var center := Vector2(size.x - r - 3.0, r + 3.0)
	draw_circle(center, r, Color(0.45, 0.3, 0.05))
	draw_circle(center, r - 1.5, TRUMP_BORDER)
	var fs := int(r * 1.15)
	draw_string(font, center + Vector2(-r, fs * 0.36), "主",
		HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0.3, 0.18, 0.0))
