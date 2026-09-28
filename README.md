# ESP32 Medication Device

ESP32 用药装置与 Flutter Android App，供 iGEM 原型开发与开源复现。**当前只继续开发 Android；iOS 工程及已有构建记录保留为历史资料，不再作为本轮交付目标。**

**小智路线已调整：目标为官方云服务，不要求团队维护自己的服务器。** 但当前 0.3.0 App 仍只有本地助手和上一阶段写的 Python 网关适配；官方设备激活与 Android 直接连接尚未实现。先看[官方云接入可行性与任务](docs/xiaozhi-official-cloud.md)。

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
  UI -. 当前仅本地运行 .-> LOCAL
  UI -. 0.3.0 可选旧方案 .-> GW[Python HTTPS 网关]
  GW -. 自建部署 .-> XZ[社区 xiaozhi-esp32-server]
  UI -. 新目标：待官方激活方式确认 .-> CLOUD[小智官方云]
```

开源 Android 代码本身不要求团队自建服务器。官方云能否接受本项目 Android 作为独立客户端，还取决于官方支持的设备激活和客户端凭据。仓库之前完成的自建网关代码是可复用的旧方案，但它不是官方服务，也不代表官方云已接通。

## 当前完成情况

| 模块 | 已实现 | 仍需完成 |
|---|---|---|
| Android App 0.3.0 | A+B 合并、持久化、演示与设备数据隔离、历史/统计/CSV、权限与生命周期处理 | Android 真机整机验收、正式发布签名 |
| BLE 原型 | 扫描、连接、Notify、分片与 CRC、文本落库后 ACK/COMMIT、重试与去重 | 与硬件组逐项实测断线、掉电、重传 |
| 正式事件同步 | 数据模型、事务保存、冲突拒绝、连续位置等 App 基础 | 正式事件解码入库、游标续传、校时、按确认范围回收设备日志 |
| 文字助手 | 本地摘要；可选在线 Provider、摘要发送确认、错误提示；另有自建网关原型代码 | 按官方认可的设备激活/客户端方式接入官方云；当前无官方账号连接验收 |
| 小智语音 / iOS | 历史或计划资料保留 | 不属于本轮交付 |

**原型时间文本不会自动成为首页、历史和助手的正式事件统计。** 设备使用动作也不等于已确认服药。本项目为科研原型，不提供诊断或剂量调整功能。

## 从哪里开始

- 小智开发分支、代码入口与验收：[小智成员交接](docs/xiaozhi-developer-handoff.md)。
- 安装、体验与编译：[Android App 说明](mobile_app/README.md)。
- 本轮分工与验收：[Android 开发路线](docs/android-roadmap.md)。
- 连接现有硬件：[A+B 联调说明](docs/member-ab-integration.md)。
- 官方云接入的限制和后续分工：[官方云接入说明](docs/xiaozhi-official-cloud.md)。
- 上一阶段自建网关的接口与数据范围：[网关协议](protocol/xiaozhi-bridge.md)、[网关操作说明](server/assistant-gateway/README.md)。

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
| `server/assistant-gateway/` | 上一阶段可运行的 Python 自建文字网关；团队新目标改为官方云 |
| `tools/python/` | 可选电脑端 BLE 调试工具，App 不依赖它运行 |
| `hardware/`、`samples/` | 硬件资料、示例数据 |
| `docs/` | 当前任务入口及历史交接记录 |

固件入口为 `firmware/esp32-c3/main/main.ino`，烧录前请按硬件组确认的板型、Arduino 库与接线操作。不要把协议目标说明视为固件已实现的证据。

代码采用 [MIT License](LICENSE)；第三方组件遵守各自许可证。不要提交 Token、私钥、个人蓝牙地址或真实用户记录。
