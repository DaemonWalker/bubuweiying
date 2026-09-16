# 分期开发计划与子 agent 协作协议

## 开发模式

整个项目按 step 分期，**每个 step 由主对话派出的一个子 agent 独立完成**。子 agent 启动时没有聊天上下文，一切所需信息必须来自本文档与 docs/ 下的文件。

## Step 一览

| Step | 名称 | 文档 | 依赖 |
|---|---|---|---|
| 01 | 规则引擎核心（牌/牌型/比大小/结算 + 测试） | [step-01-rules-engine.md](step-01-rules-engine.md) | 无 |
| 02 | 一局流程状态机（round_state）+ 测试 | [step-02-round-state.md](step-02-round-state.md) | 01 |
| 03 | 整场比赛（match_state + 存档结构）+ 测试 | [step-03-match-state.md](step-03-match-state.md) | 02 |
| 04 | 启发式 AI | [step-04-ai.md](step-04-ai.md) | 02 |
| 05 | 牌桌 UI 与出牌交互 | [step-05-table-ui.md](step-05-table-ui.md) | 02 |
| 06 | 流程 UI（亮主/进贡/扣底/结算面板） | [step-06-flow-ui.md](step-06-flow-ui.md) | 05 |
| 07 | 主菜单、比赛串联、存档接入 | [step-07-match-flow.md](step-07-match-flow.md) | 03、06 |
| 08 | 打磨（动画/音效/平衡/修 bug） | [step-08-polish.md](step-08-polish.md) | 07 |

## 子 agent 启动模板

主对话派发子 agent 时使用如下模板（替换 XX）：

```
你是执行 step-XX 的子 agent。项目：Godot 4.7 单机扑克游戏（大连打滚子），工作目录 e:\workspace\bubuweiying。

开始前按顺序阅读：
1. docs/README.md（项目与文档索引）
2. docs/code-style.md（代码规范，必须遵守）
3. docs/architecture.md（分层纪律与目录结构）
4. docs/game-rules.md（规则定稿；重点读与本 step 相关的章节）
5. docs/plan/step-XX-*.md（你的任务书）
6. docs/progress/ 下所有已有记录（尤其是前序 step 的接口摘要）

要求：
- 严格按任务书的产出清单与验收标准工作，不要做任务书之外的事
- 完成后按 docs/plan/README.md 的记录模板写 docs/progress/step-XX.md
- 运行验收标准中的测试，把命令和结果写进记录
- 若无法完成，写 docs/progress/step-XX.md 并标状态 blocked，说明卡点
```

## 现场记录模板

子 agent 完成（或中断）一个 step 后，**必须**写 `docs/progress/step-XX.md`：

```markdown
# Step XX：<名称> — 完成记录

- 状态：done / partial / blocked
- 日期：YYYY-MM-DD

## 完成内容摘要
（做了什么，三五句话）

## 产出文件清单
（新增/修改的文件路径，一行一个）

## 关键设计决策
（任务书没写死、由你拍板的点，以及原因；后续 step 需要知道的优先写）

## 对外接口摘要
（后续 step 会调用的类/方法/信号签名 + 一句话说明；示例用法）

## 测试与验证
（运行的命令、通过/失败用例数、未运行的原因）

## 已知问题与遗留事项
（bug、简化处理、待打磨点）

## 给下一个 step 的注意事项
（接口坑、需要配合改动的点）
```

## 主对话恢复现场流程

任何时候（包括会话被压缩/新开）恢复现场：

1. 读 `docs/README.md` 了解全局；
2. 读本文件确认当前处于哪个 step（结合 `docs/progress/` 里已有的记录，编号最大的 done 即为进度）；
3. 读下一个 step 的任务书 + 前序 step 的 progress 记录（重点：对外接口摘要、遗留事项）；
4. 派发子 agent。

若某 step 中断（状态 partial/blocked），新子 agent 读同一任务书 + 该 step 的 partial 记录接着做，完成后覆盖该 step 的 progress 文件。
