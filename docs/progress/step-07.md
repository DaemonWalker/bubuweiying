# Step 07：主菜单、比赛串联与存档 — 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

新增 `autoload/game.gd`（场景切换 + 持有 MatchState 的比赛总控）与 `autoload/save_system.gd`（`user://match_save.json` 读写、损坏容错），`ui/main_menu/`（新比赛/继续比赛/退出），table.gd 按 step-06 注明的替换点把 `_on_settlement_continued` 换成 MatchState 串联（结算后 `finish_round` 推进 + 自动存档，`Game.next_round_config()` 开下一局），比赛结束时结算面板提供“回主菜单/新比赛”双按钮，牌桌右上角加“退出比赛”（二次确认，放弃当前局）。配套 `tests/test_save_system.gd` 21 个用例；全量测试 644 个用例通过；临时冒烟驱动验证完整比赛闭环（26 项断言全过）。

## 产出文件清单

- `autoload/game.gd`（新增，autoload 名 `Game`）
- `autoload/save_system.gd`（新增，autoload 名 `SaveSystem`）
- `ui/main_menu/main_menu.gd`、`ui/main_menu/main_menu.tscn`（新增）
- 上述 4 个脚本的 `.gd.uid`（新增）
- `ui/dialogs/settlement_panel.gd`（修改：新增 `menu_requested` 信号，比赛结束加“回主菜单”按钮）
- `ui/table/table.gd`（修改：开局 config 来自 Game；结算串联 MatchState + 存档；退出按钮）
- `project.godot`（修改：注册两个 autoload；`run/main_scene` 改为主菜单）
- `tests/test_save_system.gd`（新增）
- `tests/test_runner.gd`（修改：注册 test_save_system）

## 关键设计决策

- **autoload 脚本不带 class_name**（沿用 table.gd 先例）：按 architecture.md 目录归属 `autoload/`，经 project.godot 注册为 `Game`/`SaveSystem` 单例。单元测试用 `load(...).new()` 实例化，不依赖 autoload 注册。
- **比赛结束即清除存档**：`finish_round` 推进后若 `is_over()`，`SaveSystem.clear_save()`——比赛已打完，没有可继续的局间点，“继续比赛”按钮随之禁用。这比存 match_over 状态再在读档时特判更干净。
- **“新比赛”立即覆盖存档**（architecture §存档既定）：`Game.new_match()` 先 `clear_save()` 再建 MatchState；首局结算前退出则无档可续，与“局中不存档”一致。
- **结算面板按钮语义**：未结束只有“下一局”（panel 本身即局间级别变化 + 进贡预告展示，点击自动开下一局）；比赛结束为“回主菜单”（`menu_requested`，先落档再走）与“新比赛”（`continued`，`Game.new_match()` 重开整场）。table 用 `_match_progress_applied` 防同一局结果重复 `finish_round`。
- **“退出比赛”二次确认**：首次点击 3 秒内按钮变“确认退出？”，再点才退出；防止误点丢掉整局进度。局中不存档，存档停留在最近一局结算点。
- **table 直接运行的兜底**：`Game.match_state == null` 时 `next_round_config()` 惰性开新比赛（编辑器 F6 单跑牌桌场景仍可用）；config 为空（比赛已结束，正常流程不可达）时回退 `Game.new_match()`。
- **存档损坏容错口径**：JSON 解析失败 / 非字典 / `version != MatchState.SAVE_VERSION` 均返回 null；主菜单“继续比赛”失败时红字提示并留在主菜单，不删损坏文件（用户数据不擅自清除）。

## 对外接口摘要

```gdscript
# Game（autoload/game.gd）
Game.match_state: MatchState              # 当前比赛；null = 未开始
Game.new_match()                          # 新比赛：覆盖存档，切到牌桌
Game.continue_match() -> bool             # 读档进牌桌；缺失/损坏返回 false（主菜单提示）
Game.finish_round(result: Dictionary)     # 结算后推进 MatchState + 自动存档（结束则清档）
Game.next_round_config() -> Dictionary    # 下一局 RoundState config；比赛结束返回 {}
Game.quit_to_menu()                       # 放弃当前局回主菜单（档停最近结算点）

# SaveSystem（autoload/save_system.gd）
SaveSystem.has_save() -> bool
SaveSystem.save_match(ms: MatchState) -> bool
SaveSystem.load_match() -> MatchState     # 缺失/损坏/版本不符返回 null
SaveSystem.clear_save()

# SettlementPanel 新增
signal menu_requested()                   # 比赛结束时“回主菜单”
```

主场景：`res://ui/main_menu/main_menu.tscn`（已在 project.godot 注册）。典型流程：

```gdscript
# 主菜单按钮 → Game.new_match() / Game.continue_match()
# 牌桌 _ready：_start_round(Game.next_round_config())
# 结算“下一局”：Game.finish_round(rs.get_result()) → _start_round(Game.next_round_config())
```

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 644，失败 0 ==`（exit code 0；step-06 的 623 + 新增 21）。新增用例覆盖：无存档 has_save/load 返回、新比赛与局间（§8 分支7 后级别/庄家/局数/进贡张数）存档往返一致、损坏容错（非法 JSON / 非字典 / 版本不符 → null）、clear_save。测试运行前备份真实存档、结束后还原，不污染玩家数据。

主场景加载验证：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --quit-after 30
```

无任何 ERROR/SCRIPT ERROR（主菜单场景正常加载）。

端到端验证（验收标准全覆盖）：临时冒烟驱动 `smoke_match.gd`（`Engine.time_scale=20`，玩家座动作全经 UI 通路——面板 signal emit / 点选手牌 + 出牌按钮 / BidPanel 回调；手动实例化 autoload 节点，因 -s 主循环脚本编译期无 autoload 全局标识符）：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://smoke_match.gd
```

结果：`== 冒烟：错误 0 个 ==`（exit code 0），26 项断言全过。流程：无存档继续禁用 → 预置旧存档后“新比赛”覆盖清除并进牌桌 → 连打 2 局（结算“下一局”串联，MatchState 逐局推进，存档内容与 `ms.to_dict()` 一致）→ 第 3 局中途退出回主菜单（MatchState 保持结算点）→ “继续比赛”恢复（级别/庄家/进贡参数与存档一致，新一局从发牌开始）→ 写入定级 10/10 的存档继续比赛 → 打到比赛结束 → 总结算画面含“新比赛/回主菜单” → 回主菜单后存档已清除、继续禁用 → 损坏存档提示并留在主菜单 → 删除存档后继续禁用。验证后已删除 smoke_match.gd（临时工具，不入库）。

验收标准覆盖情况：

- 主菜单新比赛 → 多局 → 打过 10 → 总结算：走通（打过 10 段用定级 10/10 存档加速，机制同真实对局）。
- 中途退出后“继续比赛”恢复到最近一局结算点，级别/庄家/进贡参数正确：断言 `Game.match_state.to_dict()` 逐字段一致 + 新一局 `_round_prev_levels` 与存档级别一致。
- 删除存档后“继续比赛”禁用：验证。
- 真实鼠标手感（菜单按钮、退出确认）需在编辑器中人工确认（无界面环境做不到）。

## 已知问题与遗留事项

- `JSON.parse_string` 对损坏文件会在引擎层打印一条 ERROR 日志（`load_match` 正常返回 null），属预期噪音，无法在不换解析方式的前提下消除。
- 主菜单为功能性样式（绿色底 + 居中大按钮），无美术打磨（step-08）。
- “新比赛”覆盖存档无二次确认（靠“退出比赛”有确认、主菜单按钮语义直观兜底；如需可在 step-08 加）。
- 定级 10/10 的冒烟存档中双方都满级，比赛通常在 1~3 局内结束（分支 5/6 不升级会继续），冒烟设了 10 局上限，本次实测在限额内结束。

## 给下一个 step 的注意事项

- step-08（打磨）：发牌 78 秒/局、AI 亮主即时化、结算/主菜单视觉都留待打磨；冒烟驱动模式（手动实例化 autoload + 面板 signal emit）可复用做回归。
- **-s 主循环脚本中 autoload 全局标识符（Game/SaveSystem）编译期不可见**，运行期节点存在；临时脚本用 `root.get_node("Game")` 或手动实例化（本次冒烟两种都处理了）。
- 测试入口脚本报错时进程不退出（quit 未执行），排查先看输出里的 SCRIPT ERROR——本次冒烟调试两次踩到。
- GDScript 注意：`while true` 函数的返回路径检查不认无限循环，尾部需补 `return`；Node 型变量调自定义方法返回 Variant，`:=` 推断会报 parse error，需显式标类型。
