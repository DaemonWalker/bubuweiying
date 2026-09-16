# 代码规范

## 语言与版本

- GDScript，Godot 4.7。所有脚本**必须静态类型**：变量、参数、返回值都标注类型。
- 禁止使用 `@tool`、插件、第三方库；只用引擎内置能力。

## 命名

| 对象 | 风格 | 示例 |
|---|---|---|
| 类名 / class_name | PascalCase | `RoundState` |
| 文件名 | snake_case，与类名对应 | `round_state.gd` |
| 函数 / 变量 | snake_case | `trick_winner` |
| 常量 / 枚举值 | SCREAMING_SNAKE | `MAX_LEVEL` |
| 信号 | snake_case，表事件 | `trick_finished` |
| 私有成员 | 前缀下划线 | `_pending_bid` |

## 注释

- 默认不写注释；不写"解释代码做了什么"的注释。
- 实现具体规则分支时，用一行注释引用规则文档章节，例如：`# 规则 §8 分支5：≥120 未抠底，上台不升级`。
- 对外公开的类与方法（core 全部公共 API）写简短的 docstring（`##` 开头），说明输入输出而非实现。

## 分层纪律

- `core/`：只能 `extends RefCounted`（或 `Resource`）；**禁止**出现 `Node`、`SceneTree`、`preload` UI 资源、autoload 调用。状态机用显式枚举 + 方法驱动，不用引擎动画/计时器（时间控制由 UI 层负责）。
- `ai/`：依赖 `core/`，不依赖 `ui/`。
- `ui/`：通过信号和 `get_available_actions/apply_action` 与 core 交互，**不在 UI 层实现任何规则判断**。
- 目录结构以 architecture.md 为准，新增文件先确认归属层级。

## 测试约定

- `core/` 每个类有对应 `tests/test_<类名>.gd`。
- 测试风格： plain 函数 + `assert` 风格的辅助方法（`check_eq(actual, expected, "用例名")`），全部经 `tests/test_runner.gd` 汇总运行。
- 每个测试用例名注明对应的规则章节，如 `"§7.3 主牌单张不能杀副牌棒子"`。
- 完成一个 step 前必须运行测试并在 progress 记录中写明命令与结果；无法运行（无 Godot CLI）时明确标注"未运行"。

## 其他

- 单文件控制在约 300 行以内；超出时按职责拆分。
- 不用 Magic Number：规则参数（120 分线、底牌 6 张、大王+2 级等）集中为常量，放在对应 core 文件顶部。
- 每完成一个 step 提交一次 git（commit message 含 step 编号）。
