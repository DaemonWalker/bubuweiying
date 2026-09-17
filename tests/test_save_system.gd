extends RefCounted
## SaveSystem（autoload/save_system.gd）单元测试：无存档、读写往返、比赛中途状态、
## 损坏容错（非法 JSON / 非字典 / 版本不符）、删除。运行前备份真实存档、结束后还原，避免污染。

const SAVE_SCRIPT := "res://autoload/save_system.gd"
const SAVE_PATH := "user://match_save.json"


func run(c: TestCheck) -> void:
	var backup := _backup()
	_no_save(c)
	_round_trip(c)
	_mid_match_round_trip(c)
	_corrupt_save(c)
	_clear_save(c)
	_restore(backup)


func _new_system() -> Node:
	return (load(SAVE_SCRIPT) as GDScript).new() as Node


func _no_save(c: TestCheck) -> void:
	var ss := _new_system()
	ss.clear_save()
	c.check_false(ss.has_save(), "无存档时 has_save = false")
	c.check_eq(ss.load_match(), null, "无存档时 load_match 返回 null")
	ss.free()


func _round_trip(c: TestCheck) -> void:
	var ss := _new_system()
	var ms := MatchState.new(123)
	c.check_true(ss.save_match(ms), "新比赛存档写入成功")
	c.check_true(ss.has_save(), "写入后 has_save = true")
	var loaded: MatchState = ss.load_match()
	c.check_true(loaded != null, "新比赛读档成功")
	c.check_eq(loaded.to_dict(), ms.to_dict(), "新比赛存档往返一致")
	ss.free()


func _mid_match_round_trip(c: TestCheck) -> void:
	var ss := _new_system()
	var ms := MatchState.new(77)
	c.check_true(ms.finish_round(_make_result()), "推进一局（S=75 保底，§8 分支7）")
	c.check_true(ss.save_match(ms), "局间存档写入成功")
	var loaded: MatchState = ss.load_match()
	c.check_true(loaded != null, "局间读档成功")
	c.check_eq(loaded.to_dict(), ms.to_dict(), "局间存档往返一致")
	c.check_eq(loaded.get_level(0), 6, "§8 分支7：庄家方升 1 级 + 大王追加 2 级，3 → 6")
	c.check_eq(loaded.get_level(1), 3, "抓分方级别不变")
	c.check_eq(loaded.get_dealer_side(), 0, "庄家连任（分支7 不上台）")
	c.check_eq(loaded.get_round_count(), 1, "已完成局数 = 1")
	c.check_eq(loaded.next_tribute_count(), 4, "§5 下局进贡 = 2（S=75）+ 大王加成 2")
	c.check_false(loaded.next_tribute_reversed(), "S=75 无攻守易位")
	ss.free()


func _corrupt_save(c: TestCheck) -> void:
	var ss := _new_system()
	_write_text("%%%not json%%%")
	c.check_eq(ss.load_match(), null, "非法 JSON 读档返回 null")
	_write_text("[1, 2, 3]")
	c.check_eq(ss.load_match(), null, "JSON 非字典读档返回 null")
	_write_text(JSON.stringify({"version": 999}))
	c.check_eq(ss.load_match(), null, "版本不符读档返回 null")
	ss.free()


func _clear_save(c: TestCheck) -> void:
	var ss := _new_system()
	ss.save_match(MatchState.new(5))
	ss.clear_save()
	c.check_false(ss.has_save(), "clear_save 后 has_save = false")
	c.check_eq(ss.load_match(), null, "clear_save 后 load_match 返回 null")
	ss.free()


## 庄家方 0、S=75、未抠底、底牌 1 大王 → §8 分支7（庄家升 1 级 + 大王追加 2 级）。
func _make_result() -> Dictionary:
	var r := Settlement.settle(75, false, 1, 0, false, 3, 3)
	r["dealer_side"] = 0
	r["dealer_seat"] = 2
	r["next_dealer_side"] = 0
	r["next_tribute"] = {"score": 75, "bonus_big": 1, "bonus_small": 0, "bonus_active": true}
	return r


func _write_text(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _backup() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"existed": false, "text": ""}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return {"existed": true, "text": text}


func _restore(backup: Dictionary) -> void:
	if bool(backup["existed"]):
		_write_text(backup["text"])
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
