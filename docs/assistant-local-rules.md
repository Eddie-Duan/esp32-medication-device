# App 侧本地规则助手（专家系统第一层）

本文说明 `mobile_app/lib/assistant/` 里本地规则助手的规则集和边界。它不联网、不需要账号，是助手默认的回答方式。

## 结构

```text
AssistantContext（统计摘要）
    ↓
rules/observation_rules.dart     纯函数规则层，无 Flutter 依赖，可单测
    ↓
providers/mock_assistant_provider.dart   按问题路由并组织回答
    ↓
AssistantPage
```

`AssistantProvider` 仍是唯一接口。接入在线助手或小智时新增实现，不改页面和规则层。

## 规则清单

规则函数 `evaluateObservations(context, now:)` 只做确定性判断，输出 `AssistantObservation(code, text, level)`。`level` 为 `attention` 时表示用户可能需要采取设备侧维护动作。

| code | 触发条件 | 级别 | 说明 |
|---|---|---|---|
| `no_records` | `totalCount == 0` | info | 直接返回，不再推断其它结论 |
| `never_synced` | `lastSyncAt == null` | attention | 提示统计只基于本机已有数据 |
| `blank_days` | 近 7 天存在 0 次的天 | info | 说明当天没有设备动作，**不表述为漏服** |
| `uneven_days` | 有记录的日之间极差 ≥ 2 | info | 只报波动区间，不下结论 |
| `recent_gap` | 今天往前连续 ≥ 2 天为 0 | attention | 提示检查电量、按键和蓝牙同步 |
| `unknown_time` | `unknownTimeCount > 0` | attention | 建议设备校时后重新同步 |
| `future_time` | `futureTimeCount > 0` | attention | 建议核对设备时间设置 |
| `invalid_events` | `invalidEventCount > 0` | attention | 指向历史记录查看原始信息 |
| `stale_sync` | 距上次同步 ≥ `syncStaleAfterDays`(3) 个日历天 | attention | 提示统计可能不含最新记录 |

## 问题路由

按关键字顺序匹配，先命中先回答：

1. 今天 / 次数 → 今日与近 7 天计数
2. 异常 / 无效 → 疑似无效事件
3. 最近 / 一周 / 规律 / 波动 / 趋势 → 逐日序列
4. 建议 / 注意 / 怎么办 → 输出全部观察项的事实清单
5. 其它 → 摘要 + 提示可切换在线助手

具体回答后只追加 `attention` 级别的观察；`info` 级别的观察只在“建议”入口列出，避免每条回答都变长。

## 边界（必须遵守）

- **不做诊断、不给剂量建议、不修改记录、不调用设备或外部工具。**
- **没有设备记录 ≠ 漏服。** 动作次数只代表装置被使用。
- 规则函数**不读取系统时钟**，时间由调用方以 `now` 传入，保证可测。
- 每条结论都要能由 `AssistantContext` 字段推出，便于人工复核。
- 新增规则时必须同时加单测，并保留“观察文本不出现诊断或剂量类结论”的守卫用例（见 `mobile_app/test/assistant_rules_test.dart`）。

## 相关

- 摘要字段与在线契约：[protocol/xiaozhi-bridge.md](../protocol/xiaozhi-bridge.md)
- 在线助手与网关：[server/assistant-gateway/README.md](../server/assistant-gateway/README.md)
- 官方云现状：[xiaozhi-official-cloud.md](xiaozhi-official-cloud.md)
