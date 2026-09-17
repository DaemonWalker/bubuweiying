extends Node
## 场景切换与比赛总控（architecture §存档）：持有当前比赛的 MatchState，
## 负责主菜单 ↔ 牌桌切换；每局结算后推进 MatchState 并自动存档，比赛结束则清除存档。

const MAIN_MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const TABLE_SCENE := "res://ui/table/table.tscn"

var match_state: MatchState = null  # 当前比赛；null 表示尚未开始（直接运行牌桌场景时惰性创建）


func _ready() -> void:
	randomize()


## 主菜单“新比赛”：开新 MatchState，覆盖旧存档，进入牌桌。
func new_match() -> void:
	match_state = MatchState.new(randi())
	SaveSystem.clear_save()  # architecture §存档：“新比赛”覆盖存档
	get_tree().change_scene_to_file(TABLE_SCENE)


## 主菜单“继续比赛”：读档恢复并进入牌桌；存档缺失/损坏时返回 false（由主菜单提示）。
func continue_match() -> bool:
	var ms := SaveSystem.load_match()
	if ms == null:
		return false
	match_state = ms
	get_tree().change_scene_to_file(TABLE_SCENE)
	return true


## 一局结算后推进比赛并自动存档（architecture §存档：每局结算后保存）。
## 比赛结束时清除存档：比赛已打完，没有可继续的局间点。
func finish_round(result: Dictionary) -> void:
	_ensure_match()
	if match_state.finish_round(result):
		if match_state.is_over():
			SaveSystem.clear_save()
		else:
			SaveSystem.save_match(match_state)


## 下一局的 RoundState 构造参数（牌桌开局用）；比赛已结束返回空 Dictionary。
func next_round_config() -> Dictionary:
	_ensure_match()
	return match_state.new_round_config()


## 放弃当前局回到主菜单（局中不存档，继续比赛时从最近一局结算点恢复）。
func quit_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _ensure_match() -> void:
	if match_state == null:
		match_state = MatchState.new(randi())
