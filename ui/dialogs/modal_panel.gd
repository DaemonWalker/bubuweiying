class_name ModalPanel
extends Control
## 模态面板基类：半透明遮罩 + 居下面板，子类在 _content 中填充内容。
## 打开用 _reset(title)（清空旧内容），关闭用 hide_panel()；show_error 显示红色错误行。

var _title_label: Label
var _error_label: Label
var _content: VBoxContainer


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.15, 0.12, 0.97)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.48, 0.3, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	body.add_child(_title_label)
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	body.add_child(_error_label)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	body.add_child(_content)
	visible = false


## 清空内容区并以 title 打开面板。
func _reset(title: String) -> void:
	for child in _content.get_children():
		child.queue_free()
	_title_label.text = title
	_error_label.visible = false
	visible = true


## 显示红色错误提示（如 apply_action 拒绝后的规则说明）。
func show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = true


func hide_panel() -> void:
	visible = false


func _add_info(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(760, 0)
	_content.add_child(label)
	return label


## 以网格展示一组牌，返回 CardView 列表（点击交互与可选范围由子类设置）。
func _add_card_grid(cards: Array[Card], level: int, trump: int, card_size: Vector2,
		width := 940.0, height := 240.0) -> Array[CardView]:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, height)
	_content.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(width - 24.0, 0.0)
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	scroll.add_child(flow)
	var views: Array[CardView] = []
	for card in cards:
		var view := CardView.create(card, true, Play.is_trump(card, level, trump), card_size)
		flow.add_child(view)
		views.append(view)
	return views
