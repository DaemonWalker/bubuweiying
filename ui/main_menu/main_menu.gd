extends Control
## 主菜单：新比赛 / 继续比赛（无存档时禁用）/ 退出。
## 存档损坏时“继续比赛”读取失败，提示并留在主菜单。
## 已有存档时“新比赛”需二次确认（3 秒内再点一次），防止误覆盖存档。

var _continue_button: Button
var _new_button: Button
var _error_label: Label
var _new_armed := false  # “新比赛”二次确认


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.3, 0.15)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Label.new()
	title.text = "打滚子（大连）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(title)
	_continue_button = _add_button(box, "继续比赛", _on_continue_pressed)
	_new_button = _add_button(box, "新比赛", _on_new_pressed)
	_add_button(box, "退出", func() -> void: get_tree().quit())
	_error_label = Label.new()
	_error_label.custom_minimum_size = Vector2(320, 0)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	box.add_child(_error_label)
	_refresh_continue()


func _add_button(box: VBoxContainer, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(on_pressed)
	box.add_child(button)
	return button


func _refresh_continue() -> void:
	_continue_button.disabled = not SaveSystem.has_save()


# 已有存档时首次点击进入 3 秒确认态，再点才覆盖存档开新比赛。
func _on_new_pressed() -> void:
	if SaveSystem.has_save() and not _new_armed:
		_new_armed = true
		_new_button.text = "确认新比赛？将覆盖存档"
		await get_tree().create_timer(3.0).timeout
		_new_armed = false
		if is_instance_valid(_new_button):
			_new_button.text = "新比赛"
		return
	Game.new_match()


func _on_continue_pressed() -> void:
	if not Game.continue_match():
		_error_label.text = "存档损坏或读取失败，无法继续比赛；请开始新比赛。"
		_refresh_continue()
