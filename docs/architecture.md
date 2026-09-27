# 技术架构

Godot 4.7 / GDScript / 2D / gl_compatibility。核心原则：**规则逻辑与 UI 完全分离**，`core/` 不依赖场景树，可无界面运行测试，AI 与 UI 共用同一套规则接口。

## 分层与目录结构

```
res://
├── core/                  # 纯逻辑层：RefCounted，禁止场景节点/UI API/autoload 依赖
│   ├── card.gd            # 牌：花色、点数、副本序号（区分 3 副牌中的相同牌）、分值
│   ├── deck.gd            # 162 张牌的构建、洗牌、发牌
│   ├── play.gd            # 牌型识别（单张/棒子/滚子）与两手牌的大小比较（规则 §7）
│   ├── trick.gd           # 一轮出牌：跟牌合法性、大小判定、赢家与收分
│   ├── bidding.gd         # 亮主/反主：叫价表示、优先级比较、合法叫价枚举（规则 §4）
│   ├── tribute.gd         # 进贡：数量/方向计算、贡牌与还贡的合法性（规则 §5）
│   ├── bottom.gd          # 扣底/扣王/干锅判定（规则 §6）
│   ├── settlement.gd      # 一局结算矩阵：抠底/保底、升级、特殊结束（规则 §8、§9）
│   ├── round_state.gd     # 一局的状态机：把上述模块串成完整流程
│   └── match_state.gd     # 整场比赛：两队级别、庄家、局序、比赛结束判定、序列化
├── ai/
│   ├── ai_player.gd       # AI 接口（抽象基类）
│   └── heuristic_ai.gd    # 启发式实现：记牌、算分、跟大/垫小、亮主/扣底决策
├── ui/
│   ├── main_menu/         # 主菜单：新比赛 / 继续比赛
│   ├── table/             # 牌桌场景：四家手牌、出牌区、底牌区、分数显示、动画
│   ├── dialogs/           # 亮主/反主、进贡/还贡、扣底扣王、结算面板
│   └── card_view.gd       # 单张牌的可视化（Vector Playing Cards 牌面，主牌金框/选中蓝框）
├── autoload/
│   ├── game.gd            # 场景切换与比赛总控
│   └── save_system.gd     # 存档读写
└── tests/
    ├── test_runner.gd     # 无界面测试入口
    └── test_*.gd          # 与 core/ 类一一对应
```

依赖方向：`ui → core ← ai`，`autoload → 两者`。`core/` 与 `ai/` 不得反向依赖。

## 一局的状态机（round_state.gd）

```
DEALING → BIDDING → TRIBUTE → BOTTOM → PLAYING → SETTLEMENT → 交回 match_state
```

- DEALING：发牌（逻辑瞬间完成，动画由 UI 层播放）；发牌期间接受亮主事件。
- BIDDING：发完牌后的亮主/反主倒计时窗口；超时或无人再反 → 定主（规则 §4）。
- TRIBUTE：进贡/还贡（规则 §5），首局跳过。
- BOTTOM：庄家扣底、各家扣王、干锅判定（规则 §6）。
- PLAYING：逐轮出牌直至手牌打空（规则 §7），期间累计各方得分。
- SETTLEMENT：结算矩阵（规则 §8），输出一局结果（上台/升级/下局进贡参数/特殊结束）。

状态机对外暴露 `get_available_actions(seat)` 与 `apply_action(seat, action)`，UI 和 AI 都只能通过这两个入口驱动，保证规则只在 core 内实现一次。

## AI

- `AIPlayer` 接口：`decide_bid / decide_tribute / decide_bottom_jokers / decide_play` 等，与状态机的 action 一一对应。
- 启发式 AI：逐张记牌 + 每座位缺门跟踪（跟牌垫出即绝门）；扣底优先整门扣净一门造缺门、主牌不强不扣分牌；领出先判吊主（主牌占剩余一半以上且对手未全绝主则倒着出主抽主，优先主牌滚子/棒子双调），再领"无人能压"的滚子/棒子（缺门折算安全性）与安全大牌单张（抓分方优先分牌跑分、该门 ≥2 张才出），最后小牌试探（优先对手未绝门）；跟牌"有分杀没分跑"——桌面无分且非尾盘时不主杀副、不拆棒、不动"头"，能赢时优先不拆自家棒/滚子的最小代价赢法，赢不了垫最小非分孤张；尾盘（手牌 ≤6）直接出最大牌型抢出牌权；亮主/扣王按手牌强度阈值决策（打 10 阈值 +1）。
- 接口保持稳定，后续可替换更强的实现（残局推算等）而不动 core 与 UI。

## 存档

- 路径 `user://match_save.json`；每局结算后自动保存整场比赛状态（两队级别、下局庄家、下局进贡参数、局数）。
- 局中不存档：中途退出视为放弃当前局，从最近一局结算点恢复。
- 主菜单提供"继续比赛"读取存档；"新比赛"覆盖存档。

## 测试

- 测试为纯 GDScript，入口 `tests/test_runner.gd`（`extends SceneTree`），运行：
  ```
  godot --headless --path . -s res://tests/test_runner.gd
  ```
- 本机 Godot 可执行文件（Steam 版，4.7.2）：
  ```
  "/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
  ```
- 结算矩阵（规则 §8 全部 7 个分支）、比大小（§7 全部确认过的例子）必须有对应测试用例。

## 界面与素材

- 牌面使用 Vector Playing Cards 矢量贴图（`assets/cards/`，Byron Knoll，公有领域；大王=红 Joker、小王=黑 Joker，牌背/空牌为自制 SVG），叠加主牌金框徽章/选中蓝框/悬停提亮。
- 分辨率自适应：`window/stretch/mode="canvas_items"`（已在 project.godot 配置）。
