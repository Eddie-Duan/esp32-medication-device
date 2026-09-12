# 用药装置 App · 成员 A 交接

Flutter 共用 Android / iOS 代码。当前可以不接硬件演示本地记录、统计、筛选、CSV 和文字助手；BLE 扫描与同步由成员 B 接入。首页的“设备记录”为空是正常状态。

## 已实现与待接入

| 范围 | 当前实现 |
|---|---|
| A0 平台基础 | Android / iOS 工程、依赖锁文件、蓝牙权限声明；运行时权限申请交给 B |
| A1 数据与页面 | SQLite 持久化；设备 ID + 序号去重；记录详情、今日 / 7 日统计、演示入口 |
| A4 筛选与助手 | 本地日期筛选；CSV 分享当前列表；Mock 助手每次提问重新读取数据库摘要 |
| A3 保存接口 | 事务保存、完全相同的重复包识别、冲突拒绝、连续同步位置持久化 |
| B 待完成 | 扫描 / 连接 / Notify；原型文本页；正式包校验、ACK、续传和 COMMIT |
| A5 待联调 | Android / iPhone 真机运行、分享面板、权限异常和整机断线 / 掉电验收 |

## 无硬件体验

1. 打开 App，在“概览”向下滚动，点击“导入演示数据”。
2. 首次导入保存 11 条合成记录，其中 1 条时间未知；当天导入后显示今日 2 次、近 7 天 8 次使用动作、近 7 天 1 条疑似无效。
3. 打开“历史记录”，选择日期、查看详情，点击“导出 CSV”调用手机分享面板。
4. 回到概览，向下找到“问问记录助手”；回答中的统计来自当前数据源。
5. 关闭并重开 App，再切换“演示数据”，记录仍在。重复导入不增加记录；右上菜单可清除演示数据再重新导入。

演示时间固定在首次导入时，之后统计会随日期自然变化。演示与设备使用两个数据库，清除演示数据不会删除设备记录。应用不联网调用模型，也没有小智语音功能。

## 开发与构建

本轮使用 Flutter **3.47.4** / Dart **3.13.3**、JDK **17.0.20.1**、Android compile/target SDK **36**，提交 `pubspec.lock`。复现优先使用此版本；依赖的最低 SDK 约束见 `pubspec.yaml`。

```bash
cd mobile_app
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d DEVICE_ID
```

Android 安装包位于 `build/app/outputs/flutter-apk/app-debug.apk`，用于内部测试；连接并授权 USB 调试的 Android 手机可执行 `adb install -r build/app/outputs/flutter-apk/app-debug.apk`。也可以把 APK 传到手机，从文件管理器打开安装，然后打开“用药装置”。演示功能无需蓝牙硬件。

蓝牙插件 `flutter_reactive_ble 5.5.0` 的 Android 库仍固定 compileSdk 33，本项目在 `android/build.gradle.kts` 中将该子项目调整为 36，避免 AndroidX 编译错误；无需修改本机 pub 缓存。上游问题见 [#911](https://github.com/PhilipsHue/flutter_reactive_ble/issues/911)。构建仍可能出现旧 Kotlin 插件兼容提示，后续升级 Flutter 前检查 [上游迁移进度](https://github.com/PhilipsHue/flutter_reactive_ble/issues/934)。

Android 工程当前最低 API 24（Android 7.0）。iOS 工程目标为 iOS 15+。在 Mac 安装相同 Flutter、Xcode 和需要的插件构建工具后执行 `flutter pub get`、`flutter build ios --simulator`；真机需在 Xcode 选择开发团队、配置签名，再执行 `flutter run -d DEVICE_ID`。Windows 无法验证 iOS 构建；当前没有 IPA、TestFlight 或 iPhone 验收结果。

## 接入位置

```text
models/      MedicationRecord、日期筛选、统计口径
database/    RecordRepository、SQLite、去重和同步位置
services/    演示数据、页面数据控制器、CSV
pages/       概览 / 历史 / 记录详情；预留连接卡片
assistant/   AssistantContext、Mock Provider、助手页面
ble/         留给 B 的扫描、连接和协议实现
```

B 请先阅读 [接口与联调说明](../docs/member-a-handoff.md)。`MedicationDeviceApp(connectionBuilder: ...)` 的回调始终提供设备数据库，即使用户正在查看演示数据。

统计中的“使用动作”仅计 `event_type=1`；`event_type=2` 单独统计。时间未知和未来时间不计入按日统计。历史日期筛选影响列表与 CSV；概览和助手始终展示当前数据源的今日 / 近 7 天摘要，不跟随历史列表筛选。

## 验证方式

`flutter test` 覆盖真实 SQLite 文件重开、重复与冲突、事务失败、两类数据隔离、连续位置、日期 / 异常时间、CSV 和页面交互。它们是电脑端自动化验证，不能替代手机系统权限、文件分享和 BLE 实测。

可选生成界面预览（字体路径换成自己电脑的中文字体）：

```bash
flutter test tool/preview_app_test.dart --dart-define=PREVIEW_DIR=/absolute/output/path --dart-define=PREVIEW_FONT=/absolute/chinese-font.ttf
```

真实助手以后通过新的 `AssistantProvider` 和网关接入，约定见 [xiaozhi-bridge.md](../protocol/xiaozhi-bridge.md)。当前保留本地 Mock。
