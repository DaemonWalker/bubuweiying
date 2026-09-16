# Step 02：一局流程状态机（round_state）

## 目标

实现 `core/round_state.gd`：把 step 01 的模块串成完整一局，暴露统一 action 接口，UI 与 AI 共用。

## 前置

step 01 完成。必读：`docs/progress/step-01.md`（接口摘要）、architecture.md §状态机、game-rules.md §4~§8。

## 任务

1. 状态机阶段：`DEALING → BIDDING → TRIBUTE → BOTTOM → PLAYING → SETTLEMENT`（首局跳过 TRIBUTE；无王扣底时底牌不公开；干锅分支）。
2. 统一接口：
   - `get_available_actions(seat: int) -> Array`：当前阶段指定座位可执行的动作列表。
   - `apply_action(seat: int, action) -> bool`：执行动作并推进状态，非法动作返回 false。
   - 状态查询：当前阶段、各家手牌（含扣底/扣王变动）、桌面本轮出牌、各方已得分数、底牌内容、主花色、级牌、庄家。
3. DEALING：发牌；支持发牌期间插入亮主动作（首局抢亮大王按规则 §4.2 处理，含"之后摸到的第一张花色牌定主"）。
4. BIDDING：亮/反主直到倒计时窗口逻辑关闭（时间由 UI 控制，core 提供 `close_bidding()`）；无人亮主走底牌定主分支（规则 §4.3）。
5. TRIBUTE：进贡/还贡全流程（多张贡两人分摊、各自决定数量；贡牌必须是手中最大非分牌；还贡为庄家自选非分副牌、按贡数分别返还）。
6. BOTTOM：庄家扣底、扣王（先大王后小王）、其他三家扣王与捡补偿牌、干锅判定。
7. PLAYING：首家领出（默认庄家领出第一轮，见规则 §10 待定项 3，实现为可配置）、逐轮转、收分、抠底/保底记录。
8. SETTLEMENT：调用 settlement.gd，输出一局结果结构（下一局庄家方、升级数、进贡参数、特殊结束标记）。
9. 测试：用脚本化动作模拟完整一局（含亮主、进贡、扣底、出牌到结算），断言阶段流转与结果正确；覆盖首局无进贡、干锅、抠底三种变体。

## 产出文件

`core/round_state.gd`、`tests/test_round_state.gd`（改动已有文件时列入清单）

## 验收标准

- 模拟整局测试通过：39 张手牌打完，分数守恒（各方得分 + 未分配底牌分 = 300）。
- 非法动作（非当前座位、不合规则的牌）被拒绝且状态不变。
- 测试全部通过并在 progress 记录中写明。
