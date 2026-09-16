# Step 01：规则引擎核心 — 完成记录

- 状态：done
- 日期：2026-03-09

## 完成内容摘要

实现 core/ 下 8 个纯逻辑模块（全部 RefCounted、静态类型、无场景树依赖）：牌表示、162 张牌构建/洗牌/发牌、牌型识别与比大小（§7）、一轮出牌与跟牌合法性、亮主/反主叫价（§4）、进贡计算与合法性（§5）、扣底扣王与干锅（§6）、结算矩阵与升级应用（§8、§9、§2）。配套 8 个测试文件 + test_runner，共 182 个用例全部通过。

## 产出文件清单

- `core/card.gd`（新增）
- `core/deck.gd`（新增）
- `core/play.gd`（新增）
- `core/trick.gd`（新增）
- `core/bidding.gd`（新增）
- `core/tribute.gd`（新增）
- `core/bottom.gd`（新增）
- `core/settlement.gd`（新增）
- `tests/test_check.gd`（新增，断言辅助 `check_eq/check_true/check_false` 与造牌快捷方法 `card/small_joker/big_joker`）
- `tests/test_runner.gd`（新增，extends SceneTree 的无界面入口）
- `tests/test_card.gd`、`test_deck.gd`、`test_play.gd`、`test_trick.gd`、`test_bidding.gd`、`test_tribute.gd`、`test_bottom.gd`、`test_settlement.gd`（新增）

## 关键设计决策

- **牌表示**：`Card` 三个字段 `suit`（Suit 枚举，王牌为 NONE）、`rank`（2~14，小王 16、大王 17）、`copy_index`（0~2 区分 3 副牌中的相同牌）。`same_card()` 忽略副本、`is_identical()` 含副本。
- **牌力数值化**：`Play.power(card, level, trump_suit)` 把 §3 牌力序映射为整数（大王 1000 > 小王 900 > 主级 800 > 副级 700 > 主2 600 > 副2 500 > 主花色 100+rank > 副牌 rank）。三个花色副级牌同为 700，天然"同级"。
- **比大小**：`Play.beats(lead, follow, level, trump_suit)` 要求张数相同、双方牌型合法且同牌型；首家为主则跟牌须为主，首家为副则跟牌须同花色副牌或主牌；其余判小。牌型枚举值与张数对齐（SINGLE=1/STICK=2/ROLLER=3）。
- **Trick 实例只记录不校验**：`add_play` 信任调用方；跟牌合法性由静态方法 `Trick.can_follow(hand, lead, follow, ...)` 提供（规则 §7.2：同花色组张数必须等于 min(手中同组数, 首家张数)；首家为主时"同花色组"=主牌，且级牌/2 不算该花色副牌）。round_state（step-02）负责在校验通过后调用 add_play。
- **叫价**：`Bidding.Bid{kind, suit}`；优先级即 §4.4 顺序，`beats` 用严格大于，天然排除"同数量级牌反主"；首局大王 FIRST_ROUND_JOKER 优先级最高（不可被反）。王亮的 suit 为 SUIT_UNDECIDED(-1)，由叫价者选定。首局定主花色用 `first_round_trump_suit(cards_after)`。
- **进贡**：规则未定义 S∈[116,119]，按 1 张处理（已在 docstring 注明）。贡牌合法性按"牌力不低于手中第 k 大非分牌"判定，对同牌力并列宽容。王加成是否生效由调用方传 `bonus_active`（干锅/分支5 传 false）。
- **结算**：`Settlement.settle(s, kongdi, bottom_big_jokers, bottom_small_jokers, dry_pot, dealer_level, catcher_level)` 返回 Dictionary（branch 1~7、match_over、match_winner、catcher_on_stage、结算后双方级别）。特殊结束（分支 1/2/3）优先于普通分支判定。`apply_level_up` = `min(level+steps, 10)`，仅当"已在 10 级且 steps>0"才算打过 10 赢整场（修复过"从 9 升多级误判赢"的 bug）。
- 测试入口需要 class_name 全局缓存：首次运行前需 `--headless --import` 一次。

## 对外接口摘要

```gdscript
# Card
Card.create(suit, rank, copy_index) -> Card
card.is_joker() / is_big_joker() / is_small_joker() / score_value() / same_card(o) / is_identical(o)
Card.contains_identical(hand: Array[Card], card) -> bool

# Deck（全静态）
Deck.build() -> Array[Card]              # 162 张
Deck.shuffled(seed) -> Array[Card]       # 同 seed 可复现
Deck.deal(cards) -> {"hands": Array ×4, "bottom": Array[Card]}   # 39×4 + 底 6

# Play（全静态；level=庄家方级别, trump_suit=Card.Suit）
Play.identify(cards) -> Play.Type        # INVALID/SINGLE/STICK/ROLLER
Play.is_trump(card, level, trump_suit) -> bool
Play.power(card, level, trump_suit) -> int
Play.beats(lead, follow, level, trump_suit) -> bool   # follow 是否压过 lead

# Trick
Trick.new(leader_seat, level, trump_suit)
Trick.can_follow(hand, lead, follow, level, trump_suit) -> bool   # 静态
trick.add_play(seat, cards) / is_complete() / winner_seat() / score()

# Bidding（全静态 + 内部类 Bid{kind, suit}）
Bidding.beats(new_bid, current_or_null) -> bool
Bidding.legal_bids(hand, level, current_or_null, is_first_round) -> Array[Bid]
Bidding.first_round_trump_suit(cards_after) -> int     # SUIT_UNDECIDED = -1

# Tribute（全静态；s = 上局抓分方总分）
Tribute.base_count(s) / is_reversed(s) / joker_bonus(big, small) / total_count(s, big, small, bonus_active)
Tribute.can_tribute(hand, offered, level, trump_suit) / can_return(cards, level, trump_suit)

# Bottom（全静态）
Bottom.can_discard_jokers(hand, discarding)            # 有大王须先扣大王
Bottom.can_pick_compensation(bottom_cards, picked, level, trump_suit)
Bottom.is_dry_pot(bottom_cards, level, trump_suit)

# Settlement（全静态）
Settlement.settle(s, kongdi, bottom_big, bottom_small, dry_pot, dealer_level, catcher_level) -> Dictionary
Settlement.apply_level_up(level, steps) -> {"level": int, "match_won": bool}
Settlement.Winner 枚举：NONE / DEALER_SIDE / CATCHER_SIDE
```

示例（一轮出牌）：

```gdscript
var lead: Array[Card] = [...]  # 须先 Play.identify(lead) != Play.Type.INVALID
if Trick.can_follow(hand, lead, follow, level, trump_suit):
    trick.add_play(seat, follow)
if trick.is_complete():
    var winner := trick.winner_seat()
    var gained := trick.score()
```

## 测试与验证

命令：

```
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --import   # 首次：生成全局类缓存
"/e/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . -s res://tests/test_runner.gd
```

结果：`== 测试结果：通过 182，失败 0 ==`（exit code 0）。

验收标准覆盖情况：

- §8 全部 7 分支各有用例（test_settlement.gd），含干锅作废王追加、10 级再升级赢整场。
- §9 特殊结束：0 分 / 300 分 / 抠出 3 大王且 S≥120 / 打过 10，各有用例（含"S<120 的 3 大王不终结"反例）。
- §7.3 四个确认例子各有用例（test_play.gd）：主单张杀不了副棒子、主棒子杀副棒子、垫牌判小、主单张杀副单张。
- 进贡：75→2、115→1、160→2、130→方向反转，另补 69→3（向上取整）、151→2、王加成与干锅不加成。

## 已知问题与遗留事项

- 规则未定义 S∈[116,119] 的进贡数量，按 1 张处理（docstring 已注明）；如需求方另有说法改 `Tribute.base_count` 一处即可。
- 首局大王亮主后"之后摸到的全是王"时 `first_round_trump_suit` 返回 SUIT_UNDECIDED，规则未定义此极端情形，step-02 需兜底（如改为随机花色）。
- §4.2 发完牌无人亮大王的"翻底牌比大小定庄"、§4.3 无人亮主"底牌随机抽一张定主"属于流程逻辑，留给 step-02 round_state，本 step 未实现。
- 测试中级别/主花色多为硬编码 6/红桃，用例间独立无共享状态。

## 给下一个 step 的注意事项

- step-02（round_state）组合顺序：Deck.deal → Bidding（发牌中抢亮 + 定主）→ Tribute（首局跳过）→ Bottom（庄家扣底→扣王→干锅判定）→ 循环 Trick（首家领出须 Play.identify 合法，跟牌先 can_follow 再 add_play）→ 抠底翻倍算 S → Settlement.settle。
- Trick.add_play 不做合法性校验，round_state 必须先调 can_follow（跟牌）与 Play.identify（领出）。
- 结算的 S 须由 round_state 计算：抓分方累计得分 + 抠底时底牌分×2（抠底 = 最后一轮 winner 属于抓分方）。
- Settlement 的 bottom_big/small_jokers 指"扣入底牌的王"（含其他三家扣的），干锅时虽传入也会被作废，但分支 3（3 大王特殊结束）不受干锅影响。
- 跑测试前若改了 class_name 或新增类，先 `--headless --import` 刷新全局类缓存。
- 工作目录当前不是 git 仓库（无 .git），code-style.md 要求的"每 step 提交一次"无法执行；需要主对话确认是否 `git init`。
