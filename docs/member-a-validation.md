# 成员 A 验证记录 · 2026-09-12

代码基线：`main / e362a26b3c2320537168a583f158d8fb9512df28`。验证机器为 Windows，未连接 ESP32 或手机。

| 检查 | 结果 / 范围 |
|---|---|
| `flutter analyze` | 通过，无问题 |
| `flutter test --reporter expanded` | 19 项通过：记录 / SQLite 12 项、页面 5 项、原有助手 2 项 |
| `flutter test tool/preview_app_test.dart ...` | 通过；输出概览、历史、助手 3 张演示预览 |
| `flutter build apk --debug` | 通过；输出通用内部测试 APK |
| `apksigner verify --verbose` | 通过，APK v2 签名有效 |
| APK 元数据 | 包名 `org.igem.medication.medication_device_app`；版本 `0.1.0+1`；最低 API 24、target 36；arm64-v8a / armeabi-v7a / x86_64 |
| `git diff --check` | 通过 |

工具：Flutter 3.47.4、Dart 3.13.3、JDK 17.0.20.1、Gradle 9.3.1、AGP 9.1.0、Android SDK 36、NDK 28.2.13676358；依赖版本以 `mobile_app/pubspec.lock` 为准。

数据库测试使用真实 SQLite 临时文件验证关闭重开与持久化；页面测试和预览使用内存数据替身。验证过重复 / 冲突、事务失败、连续序号缺口、模拟数据隔离、未知与未来时间、日期筛选、CSV 编码、助手刷新、读取失败重试及小屏大字体。ACK 测试仅验证“入库失败无法到达调用者确认步骤”，没有实际 BLE 发包。

构建修复：将原有 reactive_ble_mobile 5.5.0 子项目的 compileSdk 从 33 调整到 36，配置保存在仓库内。仍有插件使用旧 Kotlin Gradle 插件的迁移提示，本轮不影响 APK 构建。

尚未验证：Android 实机安装与系统分享、BLE 扫描 / 断线 / 权限、固件掉电和同步、iOS 编译签名 / 安装 / 分享。A0、A5 的真机验收不能仅凭上述自动化结果标为完成。
