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
│   └── card_view.gd       # 单张牌的可视化（代码绘制花色+数字，无美术素材）
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
- 启发式 AI：记已出牌、算剩余分牌、跟牌时按"能赢则最小代价赢、赢不了垫小牌"决策；亮主/扣底按手牌强度阈值决策。
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

- 牌面用代码绘制（圆角矩形 + 花色符号 + 数字），不依赖外部美术素材。
- 分辨率自适应：`window/stretch/mode="canvas_items"`（已在 project.godot 配置）。
