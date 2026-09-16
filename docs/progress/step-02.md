# Step 02：一局流程状态机（round_state）— 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

实现 `core/round_state.gd`：把 step-01 的模块串成完整一局的六阶段状态机（DEALING → BIDDING → TRIBUTE → BOTTOM → PLAYING → SETTLEMENT），对外暴露统一的 `get_available_actions/apply_action/close_bidding` 接口与全套状态查询。配套集成测试用脚本化动作模拟完整一局，覆盖含进贡整局、非法动作拒绝、首局抢亮大王、首局翻底牌定庄、无人亮主底牌定主、干锅、抠底七种场景。全量测试 424 个用例通过（step-01 的 182 + 新增 242）。

## 产出文件清单

- `core/round_state.gd`（新增）
- `tests/test_round_state.gd`（新增）
- `tests/test_runner.gd`（修改：注册 test_round_state）

## 关键设计决策

- **action 用 Dictionary 表示**：`{"type": ActionType, ...}`。叫价类动作完全枚举（BID 含 kind/suit，王亮展开为 4 个花色各一条）；选牌类动作（TRIBUTE/RETURN/DISCARD_BOTTOM/PLAY 等）在 `get_available_actions` 中返回**描述符**（min_count/max_count/count/to_seat），由调用方附 `cards` 具体化，`apply_action` 全权校验。避免组合爆炸式枚举。
- **发牌逐张驱动**：DEALING 阶段任何座位可提交 DEAL 动作（seat 忽略，UI 按动画节奏驱动），手牌追加顺序即摸牌顺序——首局"亮大王后摸到的第一张花色牌定主"直接由手牌顺序切片求得。
- **进贡方向（规则歧义拍板）**：进贡方恒为**本局抓分方（非庄家方）**，收贡人恒为本局庄家。§5 对 S>150 写的"默认方向（上局抓分方向庄家进贡）"在抓分方上台后字面上是自我进贡，不成立；S∈[120,150] 的"攻守易位"与本解读一致（原庄家方→新庄家方）。若需求方另有说法，改 `_enter_tribute` 一处。
- **进贡分摊**：首张贡手可贡 0~剩余张，末位贡手须恰好补足（描述符 min_count/max_count 表达）。贡牌合法性仍由 `Tribute.can_tribute` 逐人校验。
- **庄家扣底与扣王合并为一个动作**：DISCARD_BOTTOM 从 45 张手牌中选 6 张扣回，其中的王须满足 `Bottom.can_discard_jokers`（先大王后小王）。扣了王 → 底牌公开 → 判干锅；干锅则跳过其他三家扣王直接出牌。其他三家按 (dealer+1..3)%4 顺序依次 DISCARD_JOKERS + PICK_COMPENSATION 或 PASS；每次交换后重判干锅，干锅即冻结（已发生的交换不撤销，拍板）。
- **抠底/保底**：末轮赢家属抓分方 = 抠底，S = 抓分方桌面分 + 2×底牌分；否则庄家方按面值收底牌分。分数守恒口径：两方桌面分 + 底牌面值分 = 300（抠底翻倍部分不计入守恒式）。
- **王奖励生效条件**（下局进贡参数 bonus_active）：非干锅 且 分支≠5 且 比赛未结束（沿用 step-01 约定）。
- **规则未定义的兜底**：首局亮大王后全摸王 / 翻大王定庄 / 无人亮主时底牌全王 → 分别以"底牌首张花色牌 / RNG 随机花色"兜底（RNG 种子 = config seed+999）。
- **测试钩子**：config 接受预排 `deck: Array[Card]`（162 张）绕过洗牌，干锅/翻底牌等定向场景用它构造。
- 单文件约 440 行，略超 code-style 的"约 300 行"；因状态机各阶段耦合于一组共享状态，暂未拆分（拆分需引入额外中间层，收益存疑）。

## 对外接口摘要

```gdscript
# 构造（config 键全部可选，详见类 docstring）
RoundState.new({
    "is_first_round": false, "dealer_side": 0,        # 0={0,2}, 1={1,3}；首局忽略 dealer_side
    "dealer_level": 6, "catcher_level": 4,            # 级牌 = 庄家方级别
    "tribute_score": 75,                               # 上局抓分方总分 S（首局忽略）
    "tribute_bonus_big": 0, "tribute_bonus_small": 0, "tribute_bonus_active": false,
    "first_lead_seat": -1,                             # -1 = 庄家领出第一轮（§10）
    "seed": 1, "deck": [],                             # deck 为测试用预排牌
})

# 驱动（UI 与 AI 唯一入口）
rs.get_available_actions(seat) -> Array        # 动作描述符/BID 全枚举，格式见类 docstring
rs.apply_action(seat, action) -> bool          # 非法动作 false 且状态不变
rs.close_bidding() -> bool                     # BIDDING 阶段由 UI 倒计时调用（每次亮/反由 UI 重置计时）

# 状态查询
rs.get_phase() -> Phase                        # DEALING/BIDDING/TRIBUTE/BOTTOM/PLAYING/SETTLEMENT
rs.get_hand(seat) -> Array[Card]               # 实时手牌（含进贡/扣底变动）
rs.get_table_plays() -> Array                  # 本轮已出 [{"seat","cards"}]
rs.get_side_score(side) -> int                 # 桌面累计分（不含底牌）
rs.get_bottom() -> Array[Card]
rs.get_trump_suit() / get_level() / get_dealer_seat() / get_dealer_side()
rs.get_current_seat() / get_current_bid() / is_bottom_public() / is_dry_pot()
RoundState.side_of(seat) -> int                # {0,2}=0, {1,3}=1
RoundState.side_seats(side) -> Array[int]      # 升序两座

# 结果（SETTLEMENT 后）：settlement 全部键 +
# next_dealer_side / next_tribute{score,bonus_big,bonus_small,bonus_active} /
# catcher_score(S) / kongdi / dry_pot / bottom_score / in_play_scores /
# dealer_seat / dealer_side / trump_suit / level
rs.get_result() -> Dictionary
```

驱动顺序示例（后续局）：

```gdscript
while rs.get_phase() == RoundState.Phase.DEALING:
    rs.apply_action(0, {"type": RoundState.ActionType.DEAL})   # 期间可穿插 BID
# BIDDING：各座位按 get_available_actions 亮/反，最后
rs.close_bidding()
# TRIBUTE → BOTTOM → PLAYING 均按 get_available_actions 提交动作，直到 SETTLEMENT
var result := rs.get_result()
```

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 新增类后刷新全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 424，失败 0 ==`（exit code 0）。

验收标准覆盖情况：

- 模拟整局：`_full_round_with_tribute` 走完亮主→进贡（S=75 贡 2 张）→扣底→39 轮出牌→结算，断言手牌打空、`in_play_scores 之和 + bottom_score = 300`、S 计算正确、结果含下局庄家方与进贡参数。
- 非法动作：`_illegal_actions` 覆盖非当前座位出牌、手中没有的牌、非法牌型（4 张甩牌、两张不同牌）、超表叫价、非贡手进贡、贡分牌、还贡张数/牌型错误、非庄家扣底、扣底张数错误、重复扣底，并断言失败后手牌数/出牌权/阶段不变。
- 变体：首局无进贡（抢亮大王 + 翻底牌两条路径）、干锅（底牌全主、冻结、王奖励作废）、抠底（固定种子扫描命中，验证底牌分翻倍与分支 2/3/4/6）。

## 已知问题与遗留事项

- §5 进贡方向按"进贡方恒为本局抓分方"实现（S>150 的规则原文按字面不可执行），见"关键设计决策"；需求方如有不同口径改 `_enter_tribute`。
- 干锅在他人扣王+捡补偿后触发时，已发生的交换不撤销（拍板，规则未明确）。
- 极端兜底（亮大王后全摸王定主、底牌全王定主）用随机花色，规则未定义。
- 进贡张数理论上超过贡方非分牌数时无防御（实际牌局不可能发生）。
- PLAYING 阶段出牌动画节奏、亮主倒计时的计时均由 UI 层负责，core 不含时间概念。

## 给下一个 step 的注意事项

- step-03（match_state）：用 `get_result()` 的 `next_dealer_side`、`dealer_level/catcher_level`（结算后级别）、`next_tribute` 直接组装下一局 config；`match_over/match_winner` 为整场比赛结束标记（Winner 枚举见 Settlement）。首局 config 只需 `is_first_round: true`。
- step-04（AI）：选牌类动作需自行构造 `cards` 再提交（可参考 test_round_state.gd 的 `_top_non_score/_return_candidates/_follow_cards` 写法）；`apply_action` 返回 false 即非法，不会产生副作用。
- 新增/改动 class_name 后先 `--headless --import` 再跑测试；测试入口脚本报错时进程不会自动退出（quit 未执行），排查时先看输出里的 SCRIPT ERROR。
- GDScript 注意：Dictionary 取值不能 `:=` 推断类型；`Array[int]` 不能用三元表达式直接赋字面量（需 `assign`）。本 step 两处踩坑已修复。
