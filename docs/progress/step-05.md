# Step 05：牌桌 UI 与出牌交互 — 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

实现牌桌场景 `ui/table/table.tscn` + `table.gd` 与单张牌可视化 `ui/card_view.gd`（代码绘制，主牌金框、选中蓝框、悬停提亮、牌背）。玩家手牌横排在下方，点选多张后点"出牌"；按钮可用性完全由 `get_available_actions` 的 PLAY 描述符驱动，非法出牌经 `apply_action` 拒绝后即时提示。亮主/进贡/扣底按任务书约定由 HeuristicAI 对全部座位（含玩家座）自动完成；AI 出牌带 0.5~1 秒思考延时；发牌 0.5 秒/张动画（规则 §4.1），出牌位移到中央，收分有文字提示。一局走首局配置（`is_first_round: true`，随机种子），结算后显示结果面板与"再来一局"。

## 产出文件清单

- `ui/card_view.gd`（新增，class_name CardView）
- `ui/card_view.gd.uid`（新增）
- `ui/table/table.gd`（新增，场景根脚本，无 class_name）
- `ui/table/table.gd.uid`（新增）
- `ui/table/table.tscn`（新增，主场景）
- `project.godot`（修改：`run/main_scene` 指向 table.tscn；窗口 1600×900）
- `core/round_state.gd`（修改：新增只读 getter `get_last_trick_winner()`）
- `tests/test_round_state.gd`（修改：整局测试补 2 条断言）

## 关键设计决策

- **UI 不做规则判断**：按钮可用性 = 选中张数 ∈ `get_available_actions` 返回的 PLAY `count` 集合；合法性最终由 `apply_action` 判定，false 时提示"牌型须为单张/棒子/滚子，跟牌须跟同花色"。手牌排序、主牌高亮只是展示，调用 core 公共查询（`Play.is_trump/power`）。
- **每局固定首局配置**：`{"is_first_round": true, "seed": 随机}`。本 step 只要求"从发牌打到一局结束"，比赛串联（MatchState、多局）属 step-07；首局还天然跳过 TRIBUTE 阶段。
- **轮赢家获取**：core 补了 `get_last_trick_winner()`（`_last_trick_winner` 已存在只是未暴露）。不用分数差推断（0 分轮无法推断，SETTLEMENT 时 `_current_seat` 语义不明）。这是本 step 对 core 的唯一改动。
- **轮结束检测**：出牌成功后 `phase == SETTLEMENT or get_table_plays().is_empty()` 即本轮结束（core 开新一轮时会清空 table_plays）。
- **异步驱动链 + 代际失效**：`_run_dealing → _auto_pre_play → _advance_play` 全部 async 串行，`_generation` 计数在"再来一局"时使未完成的 await 静默退出，避免旧局回调污染新局。
- **发牌动画速度按规则 §4.1**（约 1 秒 2 张），整局发牌约 78 秒，偏长但忠实规则；加速/跳过留给 step-08 打磨。
- **table.gd 470 行**，超 code-style "约 300 行"（与前序 step 同样的情况：场景构建 + 流程驱动 + 交互 + 视图刷新共享大量 UI 节点状态；如后续要拆，可把 CardView 布局/中央出牌区抽成 `ui/table/hand_area.gd` 等子组件）。
- **对家手牌按数量显示**（任务书允许"背面或数量"）：名牌 + 张数标签，发牌时有牌背飞行动画。
- **底牌公开时**在左上角亮出底牌小图（含干锅标记），未公开只显示张数。

## 对外接口摘要

```gdscript
# CardView（ui/card_view.gd）
signal clicked(view: CardView)
CardView.create(card: Card, face_up := true, is_trump := false, size := CardView.DEFAULT_SIZE) -> CardView
view.set_selected(value: bool)         # 选中蓝框；上移由外部布局负责
view.card / face_up / is_trump / selected
# 注意：card 可为 null（仅 face_up=false 牌背时）；非交互展示请设 mouse_filter = MOUSE_FILTER_IGNORE

# RoundState 新增（core/round_state.gd）
rs.get_last_trick_winner() -> int      # 上一轮赢家座位，尚无已结束轮为 -1
```

主场景：`res://ui/table/table.tscn`（已在 project.godot 注册为 main_scene）。table.gd 无对外 API，内部约定供 step-06 参考：流程驱动分 `_run_dealing / _auto_pre_play / _advance_play` 三段，玩家回合置 `_player_turn` 后挂起等待按钮；step-06 可在 `_auto_pre_play` 处替换为亮主/进贡/扣底对话框交互。

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 新增 CardView 类后刷新全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 623，失败 0 ==`（exit code 0；step-04 的 621 + 新增 2：末轮赢家座位有效、抠底=末轮抓分方赢）。

端到端验证（验收标准"从发牌打到一局结束"）：无界面无法点鼠标，写了临时冒烟驱动 `smoke_table.gd`（实例化 table 场景、`Engine.time_scale=10` 加速、轮到玩家时按 AI 建议模拟"点选牌→点出牌按钮"，并注入两类非法操作），运行：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://smoke_table.gd
```

结果：`== 冒烟：玩家出牌 39 次，非法拒绝验证 18 次，错误 0 个 ==` + `== 一局结束：S=170 kongdi=false branch=5 ==`（exit code 0，无 SCRIPT ERROR）。非法验证覆盖：跟牌少选 1 张时按钮禁用；领出选两张不同牌被 apply_action 拒绝且手牌/回合不变。验证后已删除 smoke_table.gd（临时工具，不入库）。

验收标准覆盖情况：

- 发牌→一局结束、玩家全程"鼠标"出牌、非法出牌被拒绝：冒烟驱动等价验证通过；真实鼠标手感（悬停、扇形布局观感）需在编辑器中人工确认。
- 规则判断零落在 UI 层：table.gd 中无 `Play.beats/Trick.can_follow/Play.identify` 调用，唯一规则相关调用是展示用的 `Play.is_trump/power`；合法性全部来自 `get_available_actions/apply_action`。

## 已知问题与遗留事项

- 发牌动画约 78 秒/局，无加速或跳过按钮（留给 step-08）。
- AI 回合的"思考中"状态条与收分提示共用 `_status_label`，收分提示会在下一手出牌时被覆盖；无浮动 +N 分动画（step-08）。
- 结算面板是纯文字 Label（无面板底板/半透明背景），视觉简陋（step-06/08 打磨）。
- 玩家手牌在 DEALING 阶段主花色未定，主牌金框在定主后才准确（发牌期间只高亮王/级牌/2）。
- 真实鼠标交互未人工验证（无界面环境做不到），编辑器中打开主场景即可玩。

## 给下一个 step 的注意事项

- step-06（流程 UI）：替换点集中在 `table.gd` 的 `_auto_pre_play`（BIDDING/TRIBUTE/BOTTOM 三分支）与 `_run_dealing` 中的自动叫价循环；玩家座位改为弹对话框，AI 座位保留现状。BIDDING 倒计时（规则 §4.3 默认 5 秒、每次亮/反重置）由 UI 计时后调 `rs.close_bidding()`。
- 玩家座位现在也有 HeuristicAI（用于自动阶段）；引入玩家交互后注意不要再对玩家座调用 decide_*，但 `observe_play` 广播必须覆盖全部 4 个 AI（含玩家座的 AI，它还要参与后续……实际上 step-06 玩家座不再需要 AI 出牌，可考虑只保留 3 个 AI + 记牌广播调整）。
- `_generation` 代际失效模式：任何新增 async 流程都要带 gen 参数并在 await 后检查。
- 新增 class_name 后先 `--headless --import` 再跑测试；本 step 新增 CardView，`.uid` 已提交。
- GDScript 注意：常量数组（`TRICK_SLOTS[seat]`）取下标是 Variant，`+ Vector2` 后不能 `:=` 推断，需显式标类型（踩坑已修）。
