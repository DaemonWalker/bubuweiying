# Step 06：流程 UI（亮主/进贡/扣底/结算）— 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

补齐一局内除出牌外的全部流程 UI。新增 `ui/dialogs/`：BidPanel（亮主/反主按钮 + 定主倒计时）、TributePanel（进贡选张数 + 还贡选牌）、BottomPanel（庄家扣底 / 其他家扣王 / 捡补偿）、SettlementPanel（结算 + 下局进贡预告 + 比赛胜者），共用 ModalPanel 模态基类（遮罩 + 居下面板）。table.gd 按 step-05 记录的替换点重写 `_auto_pre_play`/`_run_dealing`：玩家座位在每个决策节点弹对话框，AI 座位保留自动决策并以状态栏文字展示结果；BIDDING 倒计时 5 秒由 UI 计时、每次亮/反重置、超时调 `close_bidding()`（规则 §4.3）。玩家座不再配 HeuristicAI（`_ais` 改为 Dictionary，只含 1/2/3 号座）。

## 产出文件清单

- `ui/dialogs/modal_panel.gd`（新增，class_name ModalPanel：模态基类 + 卡牌网格助手）
- `ui/dialogs/bid_panel.gd`（新增，class_name BidPanel）
- `ui/dialogs/tribute_panel.gd`（新增，class_name TributePanel）
- `ui/dialogs/bottom_panel.gd`（新增，class_name BottomPanel）
- `ui/dialogs/settlement_panel.gd`（新增，class_name SettlementPanel）
- 上述 5 个 `.gd.uid`（新增）
- `ui/table/table.gd`（重写流程对接；出牌交互与视图刷新沿用 step-05）

## 关键设计决策

- **"下一局"按 `get_result()` 手工组 config**（`next_dealer_side` + 结算后级别映射 + `next_tribute`），使非首局的 BIDDING/TRIBUTE 面板在真实游玩中可达；比赛结束则开新首局。这是刻意的最小串联，**step-07 应用 MatchState + 主菜单替换 `_on_settlement_continued`**（级别映射逻辑 MatchState 已封装）。
- **进贡交互 = 只选张数**：规则 §5 要求每张贡牌是手中最大的非分牌，玩家的真实决策只有"贡几张"（首张贡手 0~max，末位须补足）。面板用 `TributePanel.suggest_tribute`（与 `Tribute.can_tribute` 同口径的 top-N 预选）做预览，玩家选张数后确认，`apply_action` 终判。任务书"只可选规则允许的最大非分牌"由此满足。
- **还贡/捡补偿的可点牌用 core 查询限定**（`Card.score_value()==0` 且 `!Play.is_trump(...)` / 底牌非分牌），与 `Tribute.can_return` / `Bottom.can_pick_compensation` 同口径；最终合法性仍由 `apply_action` 判定，拒绝后面板重开并给规则提示（"须为非分牌副牌"等）。
- **扣王的"先大王后小王"做成 UI 动态门控**：小王只在全部大王选中后才可点；取消大王时自动取消已选小王（§6.2）。`apply_action` 仍是终判。
- **庄家扣底时底牌来源标记**：core 在 `_enter_bottom` 把 6 张底牌并入庄家手牌且不保留来源，UI 在每帧循环中维护 `_bottom_snapshot`（进入 BOTTOM 前的底牌），扣底面板用 `is_identical` 匹配标"底"角标。纯展示，不影响逻辑。
- **BIDDING 窗口驱动**：`_run_bidding_window` 每 0.1s 走表倒计时；`_ai_bid_pending` 置位时先问一圈 AI（有人叫价则重置倒计时、隔 0.6s 再问一圈，优先级严格递增故必有终）；玩家叫价经 `_on_bid_chosen` 同样重置倒计时并触发 AI 再决策。发牌期间（DEALING）同一 BidPanel 保持可点（规则 §4.1 抢亮/反）。
- **玩家无王可扣时不弹窗**：BOTTOM 队列中玩家座只有 PASS 动作时直接跳过并提示"你无王可扣"，减少无效点击。
- **非法动作一律"提示 + 重开面板"**：玩家选牌类动作若被 `apply_action` 拒绝，`while not applied` 循环重新打开同一面板，不会卡死流程。
- **结算面板数据全来自 `get_result()`**：S/抠底/分支/级别变化（`_round_prev_levels` 存本局开局级别）/底牌王追加（分支 4/7 生效、干锅与分支 5 作废）/下局进贡预告（`Tribute.total_count` 现算，进贡方 = 下局抓分方）/比赛胜者（`match_winner` 相对方换算绝对方）。
- table.gd 达 760 行，超 code-style "约 300 行"（场景构建 + 四段流程编排 + 出牌交互 + 视图刷新共享 UI 节点状态；面板本身已拆出。如 step-08 要拆，可把 PLAYING 段与手牌区抽成子组件）。

## 对外接口摘要

```gdscript
# BidPanel（ui/dialogs/bid_panel.gd，非模态，由 table 定位）
signal bid_chosen(action: Dictionary)              # action 为 BID 描述符原样回传
panel.set_bids(actions: Array, level: int)         # 传入 get_available_actions 中的 BID 项；空则隐藏
panel.set_countdown_text(text) / set_current_text(text) / hide_panel()
panel.get_bid_actions() -> Array                   # 当前展示的合法叫价（测试用）
BidPanel.bid_text(kind: int, suit: int, level: int) -> String   # “亮 ♥6 / 反 ♠6×2 / 大王×3 定 ♦主 / 抢亮大王！”

# TributePanel（进贡/还贡，模态）
signal tribute_chosen(cards: Array)                # GIVE 模式：确认进贡
signal return_chosen(to_seat: int, cards: Array)   # RETURN 模式：确认还贡（await 返回 [to_seat, cards]）
panel.open_give(hand, min_count, max_count, total, level, trump)   # 描述符驱动
panel.open_return(hand, to_name, to_seat, count, level, trump)
TributePanel.suggest_tribute(hand, count, level, trump) -> Array[Card]  # top-N 最大非分牌，必然合法
panel.get_mode() -> Mode                           # NONE/GIVE/RETURN（测试用）

# BottomPanel（扣底/扣王/捡补偿，模态）
signal discard_chosen(cards: Array)                # 庄家扣回 6 张
signal jokers_decided(cards: Array)                # 空数组 = PASS
signal compensation_chosen(cards: Array)
panel.open_discard(hand, bottom_snapshot, level, trump)   # hand 为 45 张，snapshot 标“底”
panel.open_jokers(hand, level, trump)                     # 只展示王，先大王后小王门控
panel.open_compensation(bottom, count, level, trump)
panel.get_mode() -> Mode                           # NONE/DISCARD/JOKERS/COMPENSATION

# SettlementPanel（结算，模态）
signal continued()                                 # “下一局”或“新比赛”按钮
panel.show_result(result: Dictionary, prev_levels: Dictionary, side_names: Array)

# ModalPanel 基类：_reset(title) 打开并清空内容；show_error(text)；hide_panel()；
# _add_info(text)/_add_card_grid(cards, level, trump, size) 供子类填内容。
```

table.gd 内部约定（供 step-07）：`_start_round(config)` 为唯一开局入口；`_on_settlement_continued` 是最小局间串联，**替换为 MatchState 时只需改这一个函数**（用 `ms.create_round()` 的 config，并在 `finish_round` 后接存档/主菜单）。

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 新增 5 个 class_name 后刷新全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 623，失败 0 ==`（exit code 0；本 step 无 core 改动，用例数与 step-05 持平）。

端到端验证（验收标准"完整一局从发牌到结算面板全程无需控制台操作"）：临时冒烟驱动 `smoke_flow.gd`（实例化 table 场景，`Engine.time_scale=12`，玩家动作全部经 UI 通路——BidPanel 回调 / 面板 signal emit / 点选手牌+出牌按钮；玩 5 局：第 1 局首局、第 2 局自然串联、第 3 局强制 dealer_side=1 使我方进贡、第 4/5 局强制 dealer_side=0 + 每帧抢叫争取坐庄）：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://smoke_flow.gd
```

结果：`== 冒烟：完成 5/5 局；叫价 4 进贡 2 还贡 2 扣底 2 扣王 2 捡补偿 2 结算 5；非法拒绝验证 14；错误 0 ==`（exit code 0，无 SCRIPT ERROR）。全部面板模式（叫价/进贡/还贡/扣底/扣王/捡补偿/结算）均被真实触发；14 次非法注入全部被 `apply_action` 拒绝且状态不变（贡分牌、还主牌、扣底 5 张、有大王先扣小王、捡 0 张补偿、领出两张不同牌），拒绝后面板重开、流程继续。验证后已删除 smoke_flow.gd（临时工具，不入库）。

验收标准覆盖情况：

- 每个决策节点的选项均来自 core：叫价按钮 = `get_available_actions` 的 BID 枚举；进贡/还贡/扣底/捡补偿张数 = 描述符 min_count/max_count/count；可点牌范围 = core 公共查询（与校验函数同口径）；终判全部 `apply_action`。
- 倒计时 5 秒、亮/反重置、超时 `close_bidding()`（规则 §4.3）由 `_run_bidding_window` 实现，每局非首局必经；AI 亮/反即时以状态栏 + BidPanel"当前最高"展示；定主后状态栏与比分区显示主花色/级牌/庄家。
- 真实鼠标手感（面板布局、45 张扣底网格滚动、倒计时观感）需在编辑器中人工确认（无界面环境做不到）。

## 已知问题与遗留事项

- 发牌动画仍约 78 秒/局，无加速/跳过（step-08）。
- 面板视觉为功能性样式（深底圆角 + 文字按钮），无美术打磨；BidPanel 在极端多叫价时可能较高（未加滚动）。
- 进贡分摊只让玩家选张数，不能在同等牌力的并列牌中指定具体副本（规则上无差别）。
- AI 亮/反在倒计时窗口内仍偏"即时"（间隔 0.6s 连问），无拟人化犹豫（step-08 可调）。
- 真实鼠标交互未人工验证。

## 给下一个 step 的注意事项

- step-07：替换 `_on_settlement_continued` 为 MatchState 串联（接口见 step-03 记录：`ms.create_round()` / `ms.finish_round(result)` / `ms.new_round_config()`）；结算面板的"下一局/新比赛"按钮语义届时改为"局间预告 → 自动开下一局 / 回主菜单"，可直接改 SettlementPanel 的按钮文本或加第二按钮。
- 主菜单场景切换后，table 场景会被重新实例化，`_generation` 代际失效已能正确处理残留 await。
- SettlementPanel 的 `prev_levels` 由 table 在 `_start_round` 时按 config 组装；改用 MatchState 后用 `ms.get_level(side)` 在开局时取样即可。
- 新增 class_name 后先 `--headless --import` 再跑测试；本 step 新增 ModalPanel/BidPanel/TributePanel/BottomPanel/SettlementPanel，`.uid` 已提交。
- 冒烟驱动模式（面板 signal emit + `_on_bid_chosen` + 点选模拟）可复用：step-07 验收"完整比赛闭环"时可再写同类临时脚本。
