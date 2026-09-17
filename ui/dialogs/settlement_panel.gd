class_name SettlementPanel
extends ModalPanel
## 一局结算面板（规则 §8、§9）：抓分方得分、抠底/保底、升级结果、底牌王追加、
## 下局进贡预告（§5）；比赛结束展示胜者。按钮发出 continued()（下一局/新比赛）
## 或 menu_requested()（比赛结束时回主菜单），开局与场景切换由 table/Game 决定。

signal continued()
signal menu_requested()

const BRANCH_TEXTS := {
	1: "抓分方 0 分：庄家方赢得整场比赛！",
	2: "抓分方 300 分：抓分方赢得整场比赛！",
	3: "抠出底牌 3 大王：抓分方赢得整场比赛！",
	4: "抓分方上台，底牌王追加升级",
	5: "抓分方上台，不升级",
	6: "庄家连任，双方不升级",
	7: "庄家方升 1 级，底牌王追加升级",
}


## result 为 RoundState.get_result()；prev_levels 为本局开始时双方级别（绝对 side -> int）。
func show_result(result: Dictionary, prev_levels: Dictionary, side_names: Array) -> void:
	_reset("一局结算")
	var dealer_side := int(result.get("dealer_side", 0))
	var catcher := 1 - dealer_side
	var in_play: Array = result.get("in_play_scores", [0, 0])
	var kongdi := bool(result.get("kongdi", false))
	var bottom_score := int(result.get("bottom_score", 0))
	var s := int(result.get("catcher_score", 0))
	var branch := int(result.get("branch", 0))
	var dry := bool(result.get("dry_pot", false))
	_add_info("抓分方（%s）桌面得分 %d" % [side_names[catcher], int(in_play[catcher])])
	if kongdi:
		_add_info("抠底成功：底牌 %d 分翻倍计入（§8）" % bottom_score)
	else:
		_add_info("保底：底牌 %d 分按面值归庄家方（§8）" % bottom_score)
	var total_label := _add_info("抓分方总分 S = %d" % s)
	total_label.add_theme_font_size_override("font_size", 20)
	_add_info(str(BRANCH_TEXTS.get(branch, "")))
	if dry:
		_add_info("干锅局：底牌王不追加升级、不算血（§6.4）")
	var post := {dealer_side: int(result.get("dealer_level", 0)),
		catcher: int(result.get("catcher_level", 0))}
	for side in [0, 1]:
		var after: int = post[side]
		var before := int(prev_levels.get(side, after))
		if before == after:
			_add_info("%s 级别 %d（不变）" % [side_names[side], after])
		else:
			_add_info("%s 级别 %d → %d" % [side_names[side], before, after])
	var nt: Dictionary = result.get("next_tribute", {})
	var big := int(nt.get("bonus_big", 0))
	var small := int(nt.get("bonus_small", 0))
	if big + small > 0:
		var effect := ""
		if dry or branch == 5:
			effect = "（王奖励作废）"
		elif branch == 4 or branch == 7:
			effect = "（已追加升级，并计入下局进贡）"
		_add_info("底牌王：大王 ×%d、小王 ×%d %s" % [big, small, effect])
	var match_over := bool(result.get("match_over", false))
	var button := Button.new()
	if match_over:
		_title_label.text = "比赛结束"
		var winner := int(result.get("match_winner", 0))
		var winner_side := dealer_side if winner == Settlement.Winner.DEALER_SIDE else catcher
		var win_label := _add_info("【%s 赢得整场比赛】" % side_names[winner_side])
		win_label.add_theme_font_size_override("font_size", 24)
		button.text = "新比赛"
		var menu_button := Button.new()
		menu_button.text = "回主菜单"
		menu_button.pressed.connect(func() -> void: menu_requested.emit())
		_content.add_child(menu_button)
	else:
		# 规则 §5：下局进贡方恒为下局抓分方，张数含生效的底牌王加成
		var count := Tribute.total_count(int(nt.get("score", 0)), big, small,
			bool(nt.get("bonus_active", false)))
		var payer := 1 - int(result.get("next_dealer_side", 0))
		_add_info("下局预告：%s 进贡 %d 张（§5）" % [side_names[payer], count])
		button.text = "下一局"
	button.pressed.connect(func() -> void: continued.emit())
	_content.add_child(button)
