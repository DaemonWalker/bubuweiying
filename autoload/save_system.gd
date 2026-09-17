extends Node
## 存档读写（architecture §存档）：user://match_save.json，每局结算后由 Game 自动保存。
## 只存 MatchState.to_dict() 的局间状态；文件缺失、JSON 损坏或版本不符时 load_match 返回 null。

const SAVE_PATH := "user://match_save.json"


## 是否存在存档文件。
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 把整场比赛状态写入存档；返回是否写入成功。
func save_match(ms: MatchState) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(ms.to_dict()))
	f.close()
	return true


## 读取存档恢复比赛；文件缺失、JSON 损坏或版本不符时返回 null。
func load_match() -> MatchState:
	if not has_save():
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	if int(d.get("version", -1)) != MatchState.SAVE_VERSION:
		return null
	return MatchState.from_dict(d)


## 删除存档（新比赛覆盖 / 比赛结束后不再可继续）。
func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
