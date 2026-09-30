# App 侧本地规则助手（专家系统第一层）

本文说明 `mobile_app/lib/assistant/` 里本地规则助手的规则集和边界。它不联网、不需要账号，是助手默认的回答方式。

## 结构

```text
AssistantContext（统计摘要）
    ↓
rules/observation_rules.dart     纯函数规则层，无 Flutter 依赖，可单测
    ├──→ providers/mock_assistant_provider.dart   按问题路由并组织回答
    └──→ pages/home_page.dart                     概览顶部“需要留意”卡片
    ↓
AssistantPage
```

`AssistantProvider` 仍是唯一接口。接入在线助手或小智时新增实现，不改页面和规则层。

## 规则清单

规则函数 `evaluateObservations(context, now:)` 只做确定性判断，输出 `AssistantObservation(code, text, level)`。`level` 为 `attention` 时表示用户可能需要采取设备侧维护动作。

| code | 触发条件 | 级别 | 说明 |
|---|---|---|---|
| `no_records` | `totalCount == 0` | info | 直接返回，不再推断其它结论 |
| `never_synced` | `lastSyncAt == null` 且**非演示数据** | attention | 提示无法判断数据新旧 |
| `blank_days` | 近 7 天存在 0 次的天 | info | 说明当天没有设备动作，**不表述为漏服** |
| `uneven_days` | 有记录的日之间极差 ≥ 2 | info | 只报波动区间，不下结论 |
| `recent_gap` | 今天往前连续 ≥ 2 天为 0 | attention | 提示检查电量、按键和蓝牙同步 |
| `unknown_time` | `unknownTimeCount > 0` | attention | 建议设备校时后重新同步 |
| `future_time` | `futureTimeCount > 0` | attention | 建议核对设备时间设置 |
| `invalid_events` | `invalidEventCount > 0` | attention | 指向历史记录查看原始信息 |
| `stale_sync` | 距上次同步 ≥ `syncStaleAfterDays`(3) 个日历天 | attention | 提示统计可能不含最新记录 |
| `future_sync` | `lastSyncAt` 晚于当前时间 | attention | 设备时间可能设错；此时差值为负，`stale_sync` 不会触发，必须由本项兜住 |

## 问题路由

按关键字顺序匹配，先命中先回答：

0. **漏服 / 漏吃 / 忘吃 / 该不该 / 要不要吃 / 补服 / 加量 / 减量 / 停药 / 换药 / 副作用 / 诊断** → 明确拒绝（见下）
1. 今天 / 次数 → 今日与近 7 天计数
2. 异常 / 无效 → 疑似无效事件
3. 最近 / 一周 / 规律 / 波动 / 趋势 → 逐日序列
4. 最新 / 同步 / 多久 → 最后同步时间与数据新旧
5. 时间 / 校时 / 日期 → 时间未知与未来时间的条数
6. 总共 / 一共 / 多少条 / 总量 / 全部 → 总条数与今日、近 7 天
7. 空白 / 空着 / 没记录 / 漏记 → 逐日序列 + 空档观察
8. 建议 / 注意 / 怎么办 → 输出全部观察项的事实清单
9. 其它 → 说清本地模式能答什么、答不了什么，再给当前摘要

**第 0 条必须在所有数据分支之前。** 问「我今天漏服了吗」如果先命中「今天」分支去报次数，就等于用设备动作回答了服药问题——次数不证明服药，用户会把「今天 2 次」读成「吃过了」。这类问题的回答固定为：设备记录不能回答服药判断、不做诊断/不给剂量/不调整用药，并指向医生药师，最后引导回记录本身可以问什么。

**数据类分支的措辞尽量复用规则层的原话**（`_notesFor` 按 `code` 取 `AssistantObservation.text`），而不是在 provider 里另写一套：概览页的「需要留意」卡片和助手必须说同一句话，否则两处会慢慢漂开。

具体回答后只追加 `attention` 级别的观察；`info` 级别的观察只在“建议”入口列出，避免每条回答都变长。

**兜底不再只丢一句摘要。** 用户问什么（例如「介绍一下哮喘」）都回一串统计数字，会让人以为助手在复读；现在先说清本地模式的边界与能答的话题，并提示通用健康知识要切到「在线」。

## 快捷问题

界面上的 8 个快捷问题与上面的分支一一对应，每个在本地模式下都能拿到确定答案：

```text
今天用了几次？   最近有异常吗？   查看最近一周   有什么建议？
数据是最新的吗？ 设备时间对吗？   一共有多少条记录？ 空白那几天怎么看？
```

`mobile_app/test/assistant_local_routing_test.dart` 用「回答问题不落到兜底」的断言守住这层对应关系：加了快捷问题却忘了加规则分支，测试会失败。

## 演示数据下的行为

演示数据没有设备，而且 `markSyncCompleted()` 会拒绝对演示源写入同步时间，所以：

- **不输出 `never_synced`** —— 对刚导入演示数据的用户说“尚未同步”只会让人困惑；
- `recent_gap` / `unknown_time` / `future_time` 在演示数据下**只陈述事实，不给设备维护建议**（没有设备可维护）；
- 设备记录仍然保留这些建议。

概览页的“需要留意”卡片和助手共用这套规则，所以两处文案始终一致。

## 边界（必须遵守）

- **不做诊断、不给剂量建议、不修改记录、不调用设备或外部工具。**
- **没有设备记录 ≠ 漏服。** 动作次数只代表装置被使用。
- 规则函数**不读取系统时钟**，时间由调用方以 `now` 传入，保证可测。
- 每条结论都要能由 `AssistantContext` 字段推出，便于人工复核。
- 新增规则时必须同时加单测，并保留“观察文本不出现诊断或剂量类结论”的守卫用例（见 `mobile_app/test/assistant_rules_test.dart`）。

## 相关

- 在线助手的现行边界（BYOK，Key 不出手机）：[assistant-model-access.md](assistant-model-access.md)
- 摘要字段与在线契约（网关已废弃，仅作历史）：[protocol/xiaozhi-bridge.md](../protocol/xiaozhi-bridge.md)
- 在线助手网关（已废弃，仅作历史）：[server/assistant-gateway/README.md](../server/assistant-gateway/README.md)
