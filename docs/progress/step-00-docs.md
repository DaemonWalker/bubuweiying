# Step 00：文档与规则定稿 — 完成记录

- 状态：done
- 日期：2026-03-09

## 完成内容摘要

需求讨论与规则确认完成，docs/ 文档体系建立。未写任何游戏代码。

## 关键决策（已与需求方确认，不再讨论）

- 规则全部定稿于 docs/game-rules.md，包括：活棒比大小（主杀副须同牌型）、结算矩阵 7 分支、特殊结束 = 直接赢整场、进贡数量向上取整、亮主/反主流程（发牌中可抢亮 + 发完后 5 秒倒计时窗口）、庄家确定规则（§10：亮主不夺庄，队内亮主成功者或主牌多者坐庄）。
- **排行榜不做**；60 分钟时限不做；干锅要做；中途存档要做（局间存档）。
- 玩家固定坐南（0 号位），队友与对手为 AI；AI 先启发式、接口留好以便加强。
- 牌面代码绘制，无美术素材。
- 开发模式：每 step 一个子 agent，完成后写 docs/progress/step-XX.md。

## 环境备注

- Godot 可执行文件（Steam 版 4.7.2，已验证可用）：`E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。无界面测试命令见 docs/architecture.md §测试。

## 下一步

执行 step-01（docs/plan/step-01-rules-engine.md），按 docs/plan/README.md 的子 agent 启动模板派发。
