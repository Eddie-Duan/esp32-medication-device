# Android 当前路线与交接（2026-09-23）

当前开发分支 `codex/android-xiaozhi-prep`，App 版本 `0.3.0+3`。团队只交付 Android；iOS 代码保留，自动 CI 停止，仅能手动检查。

## 本轮已经补齐

- Android 主 manifest 的联网权限；本地 / 在线助手切换，发送问题与摘要前确认。
- 可替换的网关 Provider：HTTPS、访问码、超时、大小限制、错误提示；配置只放当前页面内存，不在 APK 内预埋密钥。
- 可运行 Python 网关：mock 联调模式，以及自建小智 WebSocket 文字适配；逐句接收文字，完整结束后返回。
- 网络与协议测试；Android CI；更新当前说明并标记旧 iOS / 双平台计划为历史。

这些是代码与自动化能力，不代表 Android 真机、真实小智模型或整机链路已经验收。

## 接下来按这个顺序派发

| 顺序 / 负责人 | 任务 | 交付与验收 |
|---|---|---|
| 1 · Android 成员 | 安装本轮 APK，验证演示、历史、CSV、权限拒绝/重新授权、切后台恢复；USB 连接本机 mock 网关 | 机型/Android 版本、截图、问题清单；mock 明确标记演示 |
| 2 · 服务端成员 | 部署 xiaozhi-esp32-server，准备专用设备身份、鉴权、LLM/TTS，关闭该身份记忆/外部工具；启动本仓库网关 | 有效 HTTPS 网关地址与独立访问码；真实文字回答、超时/断线/错误码验证 |
| 3 · B + 硬件组 | 确认当前 Arduino 固件版本、BLE UUID、文本分片；验证保存成功后才 ACK、重传不重复、断线重连 | Android + ESP32 逐项联调记录；不要用第三方调试工具结果代替本 App |
| 4 · A + B + 硬件组 | 明确正式事件帧，完成解码 → 事务入正式库 → 连续 ACK/COMMIT；再做校时、游标续传、日志回收 | 真实事件出现在历史/统计/助手；未知与未来时间口径正确；断线/掉电不丢记录、不提前回收 |
| 5 · Android 成员 | 正式发布签名、覆盖升级保留数据库；按实际需求决定是否安全保存网关配置 | 团队保管密钥、可安装发布包、升级结果；不把 debug 包标作正式版 |
| 6 · Wiki 成员 | 更新架构为 Android → BLE / SQLite；可选 Android → 网关 → 自建小智；移除当前目标中的 iOS | 使用已验证证据，分别写“已实现”“已验收”“待联调”，不把计划写成已完成 |

第 1–3 项可并行。第 4 项必须以双方确认的正式协议为依据，不能凭原型时间文本推断药物、剂量或实际服药。

## 交接给组员的文件

- App 与构建：[mobile_app/README.md](../mobile_app/README.md)。
- 小智部署成员：[server/assistant-gateway/README.md](../server/assistant-gateway/README.md)、[协议](../protocol/xiaozhi-bridge.md)。
- 硬件联调：[member-ab-integration.md](member-ab-integration.md)、`protocol/` 与对应固件。
- A/B 正式入库接口：[member-a-handoff.md](member-a-handoff.md)。

无需提供 Mac。App 接小智服务也无需覆盖 ESP32 原有 Arduino 固件。若以后需要装置端麦克风/扬声器语音，再独立评估 ESP-IDF 与板型迁移。
