# Step 03：整场比赛（match_state）与存档结构 — 完成记录

- 状态：done
- 日期：2026-09-17

## 完成内容摘要

实现 `core/match_state.gd`：管理整场比赛的局间状态（两队级别、下局庄家方、局数、下局进贡参数、比赛结束与胜方），`finish_round` 接收 `RoundState.get_result()` 推进比赛，`create_round/new_round_config` 生成下一局，`to_dict/from_dict` 提供 JSON 兼容序列化。配套 `tests/test_match_state.gd` 77 个用例；全量测试 501 个用例全部通过。

## 产出文件清单

- `core/match_state.gd`（新增）
- `tests/test_match_state.gd`（新增）
- `tests/test_runner.gd`（修改：注册 test_match_state）

## 关键设计决策

- **MatchState 只存局间状态，不做规则判断**：级别推进、特殊结束、"打过 10"全部由 `Settlement.settle`（经 RoundState 结果）算好，MatchState 只搬运 `dealer_level/catcher_level/match_over/match_winner` 并换算绝对 side（Settlement.Winner 是相对本局的庄/抓）。规则逻辑仍只有一份。
- **庄家轮换按规则 §10 定稿实现**：下局庄家方 = `result.next_dealer_side`（结算唯一确定），首局庄家方未定（`SIDE_NONE = -1`，由抢亮大王/翻底牌决定）；庄家方内部谁坐庄由该局 RoundState 在亮主后决定，MatchState 仅记录 `dealer_seat` 供展示，不参与决策。因此无需注入式策略。
- **每局种子 = base_seed + 已完成局数**：序列化只存 `base_seed`，恢复后种子序列无缝延续（有测试断言）。
- **finish_round 防御性校验**：比赛已结束、缺关键字段、dealer_side 非 0/1 均拒绝（返回 false）且状态不变。
- **from_dict 兼容 JSON 反序列化**：所有数值显式 `int()` 转换（JSON 解析出 float），缺字段回退默认值（空字典恢复为全新比赛）。
- **进贡数量/方向为派生查询**：`next_tribute_count()`（首局 0）与 `next_tribute_reversed()` 由存储的 `next_tribute` 参数经 `Tribute.total_count/is_reversed` 现算，不冗余存储。方向口径沿用 step-02 拍板：进贡方恒为本局抓分方（非庄家方），收贡人为本局庄家。

## 对外接口摘要

```gdscript
MatchState.new(base_seed := 1)                 # 新比赛；每局洗牌种子 = base_seed + 已完成局数

# 状态查询
ms.get_level(side) -> int                      # side 0={0,2}，1={1,3}
ms.get_dealer_side() -> int                    # 下局庄家方；首局为 MatchState.SIDE_NONE(-1)
ms.get_dealer_seat() -> int                    # 上一局庄家座位；无已完成局为 -1
ms.get_round_count() -> int                    # 已完成局数
ms.is_over() / get_winner() -> bool / int      # winner：-1 未结束，否则 0/1
ms.get_next_tribute() -> Dictionary            # {score, bonus_big, bonus_small, bonus_active}
ms.next_tribute_count() -> int                 # 下局进贡张数（含生效的王加成；首局 0）
ms.next_tribute_reversed() -> bool             # 规则 §5 攻守易位（S∈[120,150]）

# 流程
ms.new_round_config() -> Dictionary            # 下一局 RoundState config；比赛结束返回 {}
ms.create_round() -> RoundState                # 比赛结束返回 null
ms.finish_round(result: Dictionary) -> bool    # result = RoundState.get_result()；false=拒绝且状态不变

# 序列化（只存局间状态，字段说明见 to_dict docstring）
ms.to_dict() -> Dictionary                     # JSON 兼容：version/base_seed/round_count/levels/
                                               # dealer_side/dealer_seat/next_tribute/match_over/winner
MatchState.from_dict(d: Dictionary) -> MatchState   # 兼容 JSON float 数值与缺字段
```

典型流程（供 step-07）：

```gdscript
var ms := MatchState.new(randi())
while not ms.is_over():
    var round := ms.create_round()
    # … UI/AI 驱动 round 至 SETTLEMENT …
    ms.finish_round(round.get_result())
    # 此处存档：FileAccess 写 JSON.stringify(ms.to_dict()) 到 user://match_save.json
```

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 新增 class_name 后刷新全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 501，失败 0 ==`（exit code 0；step-02 的 424 + 新增 77）。

验收标准覆盖情况：

- 多局结果序列：`_level_and_dealer_progression` 连续 4 局（分支 7→4→6→5），逐局断言级别、庄家方轮换、局数、进贡张数与攻守易位、下一局 config 各字段。
- 逢 10 必打：`_must_hit_ten` 验证 9 级 +3（升 1 + 大王追加 2）落到 10 而非跳过，且升 10 不当场获胜。
- 打过 10：10 级再达成升级条件 → 比赛结束、胜方正确。
- 特殊结束：`_special_endings` 覆盖 0 分（庄家方胜）/300 分（抓分方胜）/抠出 3 大王且 S≥120（抓分方胜），并验证结束后 `finish_round`/`create_round` 拒绝。
- 序列化往返：`_serialization_round_trip` 覆盖 to_dict→from_dict 一致、经 JSON 文本往返一致（float 兼容）、恢复后继续推进比赛、空字典恢复为初始状态。

## 已知问题与遗留事项

- 进贡方向口径继承 step-02 的拍板（进贡方恒为本局抓分方），需求方若有不同口径需改 round_state `_enter_tribute`，MatchState 不受影响。
- `dealer_seat` 仅记录上一局庄家座位（展示用）；下局庄家座位要等各局亮主结束后由 RoundState 决定（规则 §10），存档中无法预知。
- 局内不存档（architecture.md 既定）：中途退出从最近一局结算点恢复，`to_dict` 不含任何局内状态。

## 给下一个 step 的注意事项

- step-04（AI）/step-07（比赛串联）：驱动顺序为 `ms.create_round()` → 驱动 RoundState 到 SETTLEMENT → `ms.finish_round(round.get_result())` → `ms.is_over()` 判断；存档直接用 `JSON.stringify(ms.to_dict())` / `MatchState.from_dict(JSON.parse_string(...))`。
- 新增 class_name 后先 `--headless --import` 再跑测试。
- GDScript 注意：`result.has_all([...])` 可一次校验多个键；JSON 反序列化数值一律是 float，from_dict 需显式 `int()`。
