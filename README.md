# ESP32 Medication Device

一个面向开源复现的智能用药装置原型项目。当前固件代码是 ESP32-C3 / Arduino；ESP32-S3 / ESP-IDF 是待硬件组确认的演进目标。

本项目采用单仓库管理硬件固件、手机 App、BLE 协议、测试工具和项目文档，目标是让其他开发者能够根据公开代码、协议和硬件资料完成复现。

> 本项目是课程/科研原型，不构成医疗器械、诊断或用药建议。

## 系统结构

```text
传感器/按键
    ↓
ESP32 固件：采集、事件识别、Flash 日志、BLE Server（部分为目标功能）
    ↓ BLE
Flutter 手机 App：BLE Client、SQLite、历史记录、数据导出
    ↓
可选 Python 工具：电脑端协议调试、数据分析和测试
```

## 技术栈

- 当前固件：ESP32-C3 + Arduino；S3 / ESP-IDF 尚需迁移工程。
- 手机 App：Flutter + Dart，Android / iOS 共用业务代码；Android APK、iOS 云端双架构构建和模拟器首页验证通过，两端真实手机联调待完成。见 [iOS 交接](docs/ios-readiness.md)。
- BLE：手机作为 Central/GATT Client，ESP32 作为 Peripheral/GATT Server。
- 本地数据：SQLite。
- 辅助工具：Python + Bleak，可选，不是手机 App 的运行依赖。

## 目录说明

| 目录 | 内容 |
|---|---|
| `protocol/` | BLE UUID、数据包、CRC、ACK 和错误码 |
| `firmware/` | 当前 C3 Arduino 原型；部分说明仍描述 S3 / ESP-IDF 目标 |
| `mobile_app/` | Flutter 手机 App |
| `tools/python/` | 电脑端 BLE 调试和数据分析工具 |
| `server/assistant-gateway/` | 第二阶段预留的 AI 网关说明 |
| `hardware/` | 原理图、PCB、BOM 和硬件说明 |
| `docs/` | 技术报告、开发流程和测试记录 |
| `samples/` | 模拟记录和示例数据 |

## 快速开始

### 1. 获取代码

```bash
git clone https://github.com/zyc-ivsd/esp32-medication-device.git
cd esp32-medication-device
```

### 2. 查看协议

先阅读：

- [`protocol/ble-gatt.md`](protocol/ble-gatt.md)
- [`protocol/data-format.md`](protocol/data-format.md)

手机 App 和 ESP32 固件必须以协议文档为共同依据。

### 3. 编译 ESP32 固件

当前代码入口是 `firmware/esp32-c3/main/main.ino`，各模块是 Arduino `.ino` 文件。请硬件组提供已验证的 Arduino 工程组织方式、开发板配置和烧录参数；仓库目前没有可直接执行 `idf.py build` 的 S3 工程。正式 20 字节协议也不能视为已经在现有文本 Notify 原型中实现。

### 4.运行 Flutter App

安装 Flutter 和 Android SDK 后：

```bash
cd mobile_app
flutter pub get
flutter run
```

演示步骤、已验证工具版本和构建命令见 [`mobile_app/README.md`](mobile_app/README.md)。成员 B 的接入契约见 [`docs/member-a-handoff.md`](docs/member-a-handoff.md)。iOS 构建需要 macOS 和 Xcode。

### 5. 运行 Python 辅助工具

```bash
cd tools/python
python -m venv .venv
# Windows
.venv\Scripts\activate
# Linux/macOS
# source .venv/bin/activate
pip install -r requirements.txt
```

## 开源复现要求

- 固定 ESP-IDF、Flutter、Dart、Android SDK 和第三方依赖版本。
- 提交 Flutter 的 `pubspec.lock` 和 Python 的依赖锁定文件。
- 提交 `sdkconfig.defaults`、分区表和固件编译配置。
- 保持 `protocol/` 与实际固件/App 实现同步。
- 提供模拟数据，使没有硬件的开发者也能测试界面和数据库。
- 不提交密码、Token、私钥、个人蓝牙地址或未脱敏用户数据。

## 当前状态

- Flutter 成员 A：SQLite、去重、演示数据、历史 / 统计、日期筛选、CSV、数据库摘要接入 Mock 助手已实现。
- 平台：补齐 Android / iOS 工程与权限声明；Android debug APK 构建通过，iOS 尚未编译或真机验证。
- 自动化：19 项测试通过、`flutter analyze` 无问题；另生成 3 张桌面渲染的演示界面预览，非手机实拍。
- BLE：原型有文本 Notify；本 App 的扫描 / 连接、正式协议校验、ACK / COMMIT 尚待成员 B 与硬件组接入，不能以此前调试软件的联调代替本 App 验证。
- 硬件：板型、交付版本和整机联调进度由硬件组确认。
- Python 工具：作为可选调试工具保留。

## 许可证

本项目代码采用 MIT License，详见 [`LICENSE`](LICENSE)。第三方依赖仍需遵守其各自许可证。
