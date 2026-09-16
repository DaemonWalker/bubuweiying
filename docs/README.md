# 打滚子（大连）单机版 — 项目文档

2D 扑克游戏，规则为大连打滚子。Godot 4.7 + GDScript，单机 4 人（玩家 + 3 个 AI），无联机，无排行榜（已明确不做）。

## 文档索引

| 文档 | 内容 |
|---|---|
| [game-rules.md](game-rules.md) | 游戏规则定稿。所有规则争议的最终依据，代码注释用 `规则 §x.y` 引用 |
| [architecture.md](architecture.md) | 技术架构：分层、目录结构、状态机、存档、测试方式 |
| [code-style.md](code-style.md) | 代码规范：命名、类型、注释、测试约定 |
| [plan/README.md](plan/README.md) | 分期开发计划与子 agent 协作协议（如何分 step、如何记录与恢复现场） |
| [plan/step-XX-*.md](plan/) | 每个开发 step 的任务书 |
| [progress/](progress/) | 每个 step 完成后由子 agent 填写的现场记录 |

## 开发模式

本项目按 step 分期开发，每个 step 由主对话派出**一个子 agent**完成：

1. 主对话按 [plan/README.md](plan/README.md) 的启动模板派发子 agent；
2. 子 agent 完成代码 + 测试，并按模板写 `docs/progress/step-XX.md` 现场记录；
3. 主对话验收后推进下一个 step；
4. 任何时刻主对话可通过阅读 `docs/` 恢复完整现场，无需依赖聊天历史。

## 环境

- Godot **4.7**（本机为 Steam 版 4.7.2），渲染 `gl_compatibility`，2D 项目
- 可执行文件路径：`E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（用于无界面测试，见 architecture.md §测试）
