# iOS 开发交接：没有本地 Mac 也能先推进

> 历史资料（2026-09-23 归档）：团队已决定本轮仅开发 Android，不再安排 iPhone 部署。以下保留当时验证事实；当前任务见 [Android 路线](android-roadmap.md)。

本轮基于 A+B 合并版开发，分支 `codex/ios-readiness`，目标 iOS 15+。Android 与 iOS 共用 Flutter 的页面、SQLite、协议、CSV 和助手代码，不另写一套 App。

2026-09-17 验证：共用 Dart 逻辑在 Windows 通过静态检查与 **50 项测试**；最终代码 `bdf8fe1` 在云端 macOS 再次通过分析、50 项测试、模拟器编译及未签名 iPhone 编译。模拟器成功打开首页，截图识别到“设备记录”和“历史记录”，并已人工查看。[查看最终构建记录](https://github.com/zyc-ivsd/esp32-medication-device/actions/runs/35122743488)。这不是 iPhone 蓝牙实测或签名分发结果。

启动检查已由“启动后固定等待 8 秒截图”改为等待页面实际出现，保留运行日志，并在始终未出现首页时失败。此前有一次命令成功但截图为空白，故不能只依据启动命令返回值判断界面可用。

## 本轮改动

| 模块 | 已写入代码 | 后续验收 |
|---|---|---|
| 蓝牙权限 | iOS 等待 CoreBluetooth 授权；不调用 Android 权限及 SDK 查询；拒绝后可打开应用设置 | iPhone 首次允许、拒绝后再允许、蓝牙关闭 |
| 前后台 | 进入后台暂停扫描和连接，保留已存数据；返回前台按自动重连开关恢复；手动断开不恢复 | 锁屏、切应用、接电话、同步中切后台 |
| 页面和分享 | BLE 页避开刘海和底部手势区域；iPhone 横竖屏、大字和 iPad 分享锚点测试 | 系统分享面板、真实 CSV 内容、最大字体 |
| 原生依赖 | 使用 Swift Package Manager；根据云端日志移除多余的 CocoaPods 配置 | 云端 Xcode 构建及真机运行 |
| 云端验证 | GitHub macOS：分析、测试、模拟器编译、未签名真机编译、模拟器启动截图 | 查看对应提交的 Actions 结果；不能用代码提交替代构建成功 |

当前采用**前台同步**。返回 App 后重新握手、重新请求原型快照，数据库去重；不是后台持续接收，也不是正式协议的游标续传。不要为此直接添加后台蓝牙声明：后台任务、状态恢复和耗电需要独立开发与实测。

## 不需要 Mac 的工作方式

1. 切换到 `codex/ios-readiness`，进入 `mobile_app`。使用 Flutter 3.47.4 / Dart 3.13.3。
2. 每次改完执行 `flutter pub get --enforce-lockfile`、`flutter analyze`、`flutter test`。
3. 推送此分支的 App 改动，GitHub 自动启动 [iOS build check](https://github.com/zyc-ivsd/esp32-medication-device/actions/workflows/ios-check.yml)。选择对应提交检查每步结果。`ios-validation-提交哈希` 是体积较小的日志和启动截图，`ios-app-bundles-提交哈希` 是构建包，产物均保留 7 天。
4. 成功运行会包含模拟器 `.app` 压缩包和未签名 iPhone `.app` 压缩包。这两种包都不能直接发给 iPhone 用户安装；截图只说明模拟器启动状态。

标准 macOS 执行器用于本公开仓库的自动化构建，无须先准备 Apple 签名密钥。工作流当前监控此开发分支及 PR；以后改分支或合入 main 时，应相应调整 push 分支范围。

## 接下来怎么分工

| 人员 | 现在可以做 | 完成标准 |
|---|---|---|
| A / 页面与数据 | 共用页面、筛选、CSV、大字和横屏；确保演示数据与设备数据隔离 | 自动化测试通过，补实际 iPhone 截图 |
| B / 通信 | 与硬件组冻结正式事件协议，再接入 A 的保存接口；保留先保存后 ACK | 原型文本升级为正式事件，断线重传不丢不重 |
| 能借到 Mac 的成员 | 配置签名，把同一分支装到 iPhone，执行下表 | 留下系统版本、提交号、每项结果及日志 |
| Wiki 成员 | 写 Android/iOS 共用架构、授权→握手→保存→确认流程、验证方法 | 明确“已实现 / 构建验证 / 真机待测”，不把计划写成已完成 |

## 拿到 Mac 和 iPhone 后

安装匹配的 Flutter 和 Xcode；当前锁定的依赖通过 Swift Package Manager 构建，无须额外配置 CocoaPods。在 `mobile_app` 执行：

```bash
flutter pub get --enforce-lockfile
flutter build ios --simulator --debug
open ios/Runner.xcworkspace
```

在 Xcode 的 Runner → Signing & Capabilities 选择开发团队；连接并信任 iPhone，按系统提示开启开发者模式，再用 `flutter devices`、`flutter run -d 设备ID` 安装。个人 Apple 账号可通过 Xcode 测试自己的设备；TestFlight 分发需要相应开发者计划和签名配置。不要把证书或私钥提交到仓库。

| 真机检查 | 通过标准 |
|---|---|
| 首次安装 / 拒绝后恢复 | 授权提示正常；拒绝有说明；设置中允许后可以重新扫描 |
| 扫描和连接 | 在 App 内找到 ESP32-C3，收到 READY 后才同步；无需系统蓝牙配对 |
| 数据接收 | 使用 A+B 配套固件；收到数据并保存后 ACK，重开 App 数据还在 |
| 中断与恢复 | 同步时锁屏 / 切后台，回到前台可重连并重复同步，无重复数据 |
| 用户控制 | 手动断开或关闭自动重连后，不擅自连回 |
| A 功能回归 | 演示、筛选、统计、CSV 分享和助手均可操作；演示不污染设备库 |

没有 iPhone 的 BLE 实测记录前，不能宣称“iOS 已全面适配”。原型时间文本仍在连接页，尚未进入正式事件统计；小智语音、正式协议和 TestFlight 也不包含在本轮完成项中。

参考：[Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)、[Flutter iOS 发布](https://docs.flutter.dev/deployment/ios)、[Apple 个人账号与开发者计划](https://developer.apple.com/help/account/basics/about-your-developer-account)、[GitHub 执行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
