extends SceneTree
## 无界面测试入口：godot --headless --path . -s res://tests/test_runner.gd


func _init() -> void:
	var c := TestCheck.new()
	var suite_paths := [
		"res://tests/test_card.gd",
		"res://tests/test_deck.gd",
		"res://tests/test_play.gd",
		"res://tests/test_trick.gd",
		"res://tests/test_bidding.gd",
		"res://tests/test_tribute.gd",
		"res://tests/test_bottom.gd",
		"res://tests/test_settlement.gd",
		"res://tests/test_round_state.gd",
		"res://tests/test_match_state.gd",
		"res://tests/test_ai_match.gd",
	]
	for path in suite_paths:
		var suite = (load(path) as GDScript).new()
		suite.run(c)
	print("== 测试结果：通过 %d，失败 %d ==" % [c.passed, c.failed])
	quit(0 if c.failed == 0 else 1)
