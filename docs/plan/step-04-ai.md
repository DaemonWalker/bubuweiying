# Step 04：启发式 AI

## 目标

实现 `ai/ai_player.gd`（接口）与 `ai/heuristic_ai.gd`（实现），让 3 个 AI 能完整打完一局，行为符合规则且有基本策略。

## 前置

step 02 完成。必读：`docs/progress/step-01.md`、`step-02.md`（round_state 的 action 接口）、game-rules.md 相关章节。

## 任务

1. `ai/ai_player.gd`：抽象接口，方法对应 round_state 的各类动作：`decide_bid`、`decide_tribute_give`、`decide_tribute_return`、`decide_bottom`、`decide_bottom_joker`、`decide_play`（首家领出 / 跟牌）。
2. `ai/heuristic_ai.gd` 策略要求：
   - 记牌：跟踪已出的王、级牌、分牌。
   - 领出：优先出非分小牌试探；手上有大滚子/大棒子时按局势使用；队友已赢的轮次不抢。
   - 跟牌：能赢则以最小代价赢；赢不了则垫最小的非分牌；抓分方 AI 在末轮评估抠底。
   - 亮主/反主：按主牌长度与王数量阈值决策。
   - 扣底：优先扣非分小牌；扣王按规则先大王后小王，评估干锅风险。
   - 进贡/还贡：贡牌取规则允许的最大非分牌；还贡选最小非分副牌；多张贡时两 AI 间按约定策略分摊（如各一半，奇数由庄家上家多贡）。
3. 测试：4 个 AI 自动对局（无 UI），从发牌打到结算，能完整跑完至少 20 局不死锁、不非法动作、分数守恒。

## 产出文件

`ai/ai_player.gd`、`ai/heuristic_ai.gd`、`tests/test_ai_match.gd`

## 验收标准

- 20 局 AI 自动对局全部正常结束（断言：每局进入 SETTLEMENT、总分守恒、无非法动作）。
- AI 决策有注释引用规则章节处遵守 code-style.md 的注释约定。
