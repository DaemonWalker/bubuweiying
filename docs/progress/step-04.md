# Step 04：启发式 AI — 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

实现 `ai/ai_player.gd`（抽象接口，方法与 RoundState 动作一一对应）与 `ai/heuristic_ai.gd`（启发式实现：逐张记牌 + 阈值策略）。配套 `tests/test_ai_match.gd`：4 个 HeuristicAI 无 UI 自动对局 20 局（含首局、攻守易位区间 S、王奖励进贡等变体），每局断言无非法动作、不死锁、进入 SETTLEMENT、手牌打空、分数守恒、S 计算正确。全量测试 621 个用例通过（step-03 的 501 + 新增 120）。

## 产出文件清单

- `ai/ai_player.gd`（新增）
- `ai/heuristic_ai.gd`（新增）
- `tests/test_ai_match.gd`（新增）
- `tests/test_runner.gd`（修改：注册 test_ai_match）

## 关键设计决策

- **decide_* 全部接收 `RoundState` + 座位号**：AI 通过 core 公共查询接口（get_hand/get_level/get_trump_suit/get_table_plays/get_available_actions 等）读状态，返回具体化的 action Dictionary 直接交给 `apply_action`。AI 不接触别家手牌，信息公平。
- **记牌**：`_played` 字典按 "suit:rank" 计已出副本数（王/级牌/分牌由此统一推导），驱动方在每手 PLAY 成功后对所有 AI 调 `observe_play`。主要用于"安全牌型"判定：某滚子/棒子的所有可压牌（同组更大 / 主杀副同牌型）剩余未现副本都不足张数时，判定无人能压、领出它。底牌 6 张计入"未现"，判定偏保守（可接受）。
- **亮主/反主阈值**：按拟任主花色下的主牌张数决策（级牌×1/×2/×3 分别需 ≥16/15/14（见常量 BID_LEVEL_*_MIN，反主 +1）；3 王亮必叫并按最强花色定主；首局抢亮大王必抢。162 张牌主牌约 63 张、人均 ~15.7，阈值定在均线上方。
- **进贡分摊约定**（任务书允许 AI 间约定）：首贡手贡 floor(剩余/2)，末位贡手补足（奇数由末位多贡）。贡牌 = 手中最大的非分牌（天然满足 §5 合法性）；还贡 = 最小非分副牌。
- **扣底**：优先扣非分副牌（扣出优先序：非分副牌 < 分牌副牌 < 非分主牌 < 分牌主牌）；主牌 ≥20 张且有大王时扣全部王赌 §8 分支7 的王追加升级，但底牌至少留 1 张副牌防全主干锅（§6.4），另有干锅兜底改扣非王牌。
- **其他三家扣王**：仅庄家方成员在底牌已公开（庄家已扣王）时追加扣全部王，且模拟后判干锅则放弃；抓分方一律不扣（简化策略，已记录为遗留项）。
- **领出**：末轮（手牌 ≤3）出最大牌型（抓分抢抠底 / 庄家保底）；否则优先领记牌判定"安全"的滚子 > 棒子；默认不拆对子的最小非分副牌单张试探。
- **跟牌**：当前最大是对手且同花色组够张数时，枚举同牌型组合取能压过的最小牌力一手（最小代价赢）；赢不了垫最小非分牌；队友已赢则改为优先喂分。分组逻辑与 `Trick._in_lead_group` 同口径（首家为主则主牌一组，否则该花色副牌一组）。
- **驱动节奏**（测试即参考实现）：DEALING 每发一张问一圈叫价；BIDDING 每轮全座位问一圈、无人叫价则 `close_bidding()`（叫价优先级严格递增，天然有界）；TRIBUTE/BOTTOM 每步找唯一有动作的座位路由到对应 decide_*；PLAYING 由 `get_current_seat()` 驱动，出牌成功后广播 `observe_play`。

## 对外接口摘要

```gdscript
# AIPlayer（抽象基类，ai/ai_player.gd）；HeuristicAI 为可用实现
ai.start_round(rs: RoundState, seat: int)        # 新一局：清记牌（级牌此时已知）
ai.observe_play(seat: int, cards: Array[Card])   # 每手 PLAY 成功后对全部 AI 广播（记牌）
ai.decide_bid(rs, seat) -> Dictionary            # BID action 或 {} 不叫（DEALING/BIDDING）
ai.decide_tribute_give(rs, seat) -> Dictionary   # TRIBUTE {"cards"}
ai.decide_tribute_return(rs, seat) -> Dictionary # RETURN {"to_seat","cards"}
ai.decide_bottom(rs, seat) -> Dictionary         # DISCARD_BOTTOM {"cards"×6}
ai.decide_bottom_joker(rs, seat) -> Dictionary   # DISCARD_JOKERS / PICK_COMPENSATION / PASS
ai.decide_play(rs, seat) -> Dictionary           # PLAY {"cards"}（领出或跟牌）
```

用法：见 `tests/test_ai_match.gd` 的 `_run_round`（完整驱动循环）与 `_act_one`（TRIBUTE/BOTTOM 路由）。

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 新增 class_name 后刷新全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 621，失败 0 ==`（exit code 0，无 SCRIPT ERROR；全量约 1.2 秒）。

验收标准覆盖情况：

- 20 局 AI 自动对局全部正常结束：每局断言无非法动作（illegal==0）、steps < 3000（不死锁）、进入 SETTLEMENT、四家手牌打空、`in_play_scores 之和 + bottom_score == 300`（分数守恒）、`catcher_score == 抓分方桌面分 + (抠底 ? 2×底牌分 : 0)`。共 20×6=120 个新用例。
- 对局变体：首局 ×2（抢亮大王路径）、dealer_side 轮换、级别 3~10、S ∈ {55~200} 含攻守易位区间（130/145）与大额进贡（200 → 6 张）、王奖励进贡（bonus_active）×6。
- 另用临时统计脚本（验证后已删除）确认策略真实生效：18 局非首局全部有人亮主（共 29 次叫价含反主）、抠底 9 局、亮底 14 局、干锅 5 局、结算分支覆盖 {3,4,5,6,7}、平均 S≈141.5。
- 决策注释引用规则章节处遵守 code-style.md（`# 规则 §x.y` 一行注释 + core 公共 API docstring）。

## 已知问题与遗留事项

- `heuristic_ai.gd` 432 行，超 code-style 的"约 300 行"（与 step-02 同样情况：策略各阶段共享记牌/牌力缓存状态，拆分需引入中间层，收益存疑；如后续要拆，记牌+安全判定可抽为 `ai/card_memory.gd`）。
- 抓分方 AI 永不主动扣王（放弃 §8 分支4 的王追加升级与分支3 的 3 大王特殊结束机会）；庄家方扣王也较保守（仅加码已亮底的局面）。
- 记牌不含进贡/还贡的牌流信息（贡牌非公开，AI 无法得知，属公平信息）；底牌未现计入保守判定。
- 领出试探可能拆开非对子场合无影响；对子只出单张的"活棒"拆分未做（跟棒子时只按同牌型压或不压，不会拆滚子凑棒子等精细操作）。
- AI 无时间概念，亮主倒计时的"每次亮/反重置"由 UI 层实现（architecture.md 既定）。

## 给下一个 step 的注意事项

- step-05/06（UI）：人类玩家不占 AI 座位；驱动 AI 时复用 `tests/test_ai_match.gd` 的循环结构即可。发牌动画期间穿插 `decide_bid`；BIDDING 倒计时由 UI 计时后调 `close_bidding()`。
- `observe_play` 必须由驱动方在每手出牌成功后调用（含人类玩家的出牌），否则 AI 记牌缺失、安全牌型判定失真。
- AI 返回的 action 均可直接 `apply_action`；接口约定"返回 {} = 不行动"，仅允许在可跳过的场合（叫价、其他三家扣王）。
- 新增 class_name 后先 `--headless --import` 再跑测试；本 step 新增 AIPlayer / HeuristicAI 两个类，`.uid` 文件已随源码提交。
