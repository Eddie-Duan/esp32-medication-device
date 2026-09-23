# ESP32 Medication Device

ESP32 用药装置与 Flutter Android App，供 iGEM 原型开发与开源复现。**当前只继续开发 Android；iOS 工程及已有构建记录保留为历史资料，不再作为本轮交付目标。**

## 系统组成

```mermaid
flowchart LR
  HW[传感器 / 按键] --> FW[ESP32-C3 Arduino 原型固件]
  FW -->|BLE 时间文本| BLE[Android 连接页]
  BLE --> DB1[原型文本 SQLite]
  FW -. 正式事件协议待接入 .-> DB2[正式事件 SQLite]
  DEMO[合成演示数据] --> DB3[演示 SQLite]
  DB2 --> UI[历史 / 统计 / CSV / 助手摘要]
  DB3 --> UI
  UI --> LOCAL[默认本地规则助手]
  UI -->|用户启用并同意发送摘要| GW[Python HTTPS 网关]
  GW -->|WebSocket 文字问答| XZ[自建 xiaozhi-esp32-server]
```

小智接入放在 Android 与服务器之间，不要求把现有 Arduino 固件改成 ESP-IDF。ESP32 直接运行小智语音固件是另一项硬件迁移工作，不属于当前方案。

## 当前完成情况

| 模块 | 已实现 | 仍需完成 |
|---|---|---|
| Android App 0.3.0 | A+B 合并、持久化、演示与设备数据隔离、历史/统计/CSV、权限与生命周期处理 | Android 真机整机验收、正式发布签名 |
| BLE 原型 | 扫描、连接、Notify、分片与 CRC、文本落库后 ACK/COMMIT、重试与去重 | 与硬件组逐项实测断线、掉电、重传 |
| 正式事件同步 | 数据模型、事务保存、冲突拒绝、连续位置等 App 基础 | 正式事件解码入库、游标续传、校时、按确认范围回收设备日志 |
| 文字助手 | 本地摘要；可选在线 Provider、摘要发送确认、错误提示；Python 小智协议适配网关 | 部署团队小智服务后真实问答联调 |
| 小智语音 / iOS | 历史或计划资料保留 | 不属于本轮交付 |

**原型时间文本不会自动成为首页、历史和助手的正式事件统计。** 设备使用动作也不等于已确认服药。本项目为科研原型，不提供诊断或剂量调整功能。

## 从哪里开始

- 安装、体验与编译：[Android App 说明](mobile_app/README.md)。
- 本轮分工与验收：[Android 开发路线](docs/android-roadmap.md)。
- 连接现有硬件：[A+B 联调说明](docs/member-ab-integration.md)。
- 启动网关、接入自建小智：[服务端操作说明](server/assistant-gateway/README.md)。
- 接口与数据范围：[助手协议](protocol/xiaozhi-bridge.md)。

```bash
git clone https://github.com/zyc-ivsd/esp32-medication-device.git
cd esp32-medication-device
# 本轮开发分支；合入 main 后可直接使用 main。
git switch codex/android-xiaozhi-prep
cd mobile_app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

使用 Flutter 3.47.4、Dart 3.13.3、JDK 17、Android SDK 36；最低 Android 7.0 / API 24。打开 App 导入演示数据即可体验，无需硬件或服务器。Android 自动检查配置见 [.github/workflows](.github/workflows/README.md)，实际通过情况以对应提交的日志为准。

## 仓库目录

| 目录 | 用途 |
|---|---|
| `firmware/` | ESP32-C3 Arduino 原型；S3 / ESP-IDF 是早期目标，尚非可编译迁移工程 |
| `mobile_app/` | Flutter Android 主应用；保留历史 iOS 工程 |
| `protocol/` | BLE 和助手协议，共同接口依据 |
| `server/assistant-gateway/` | 可运行的 Python 文字网关、协议测试 |
| `tools/python/` | 可选电脑端 BLE 调试工具，App 不依赖它运行 |
| `hardware/`、`samples/` | 硬件资料、示例数据 |
| `docs/` | 当前任务入口及历史交接记录 |

固件入口为 `firmware/esp32-c3/main/main.ino`，烧录前请按硬件组确认的板型、Arduino 库与接线操作。不要把协议目标说明视为固件已实现的证据。

代码采用 [MIT License](LICENSE)；第三方组件遵守各自许可证。不要提交 Token、私钥、个人蓝牙地址或真实用户记录。
