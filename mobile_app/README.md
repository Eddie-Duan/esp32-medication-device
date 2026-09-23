# 用药装置 Android App · 0.3.0

Flutter / Dart 开发，A 的数据与页面已与 B 的 BLE 原型合并。本轮集中交付 Android；保留 iOS 历史工程，但不要求 Mac 或 iPhone 验收。

## 安装和体验

使用本轮 `app-debug.apk` 内部测试包：传到 Android 手机，从文件管理器打开，允许该来源安装，然后打开“用药装置”。Android 7.0 / API 24 以上可安装；是否支持目标手机蓝牙仍需实测。

1. 无硬件：概览 → 导入演示数据 → 历史记录 / 日期筛选 / 详情 / 导出 CSV。
2. 首次导入保存 11 条合成记录（含 1 条时间未知），当日显示今日 2 次、近 7 天 8 次使用动作。日期变化后统计自然变化。
3. 有硬件：概览 → 设备连接 → 授予蓝牙权限 → 扫描连接硬件组的设备；完整步骤见 [A+B 联调](../docs/member-ab-integration.md)。
4. 现有原型接收的是时间文本，保存在独立原型数据库，**不会进入正式历史、统计及助手摘要**。正式事件解码还需与固件组完成。
5. 概览 → 问问记录助手：默认按本地规则回答，不联网。

设备事件、演示事件、原型时间文本分别存储。清除演示数据不会删除设备数据。覆盖安装要求包名相同、签名一致且版本号允许；若提示签名冲突，先导出需要保留的数据，不要直接卸载旧版。

## 在线文字助手

在助手右上角“回答方式”菜单选择“在线助手设置”，填写团队网关完整地址（例如 `https://assistant.example.org/v1/assistant/chat`）和**网关访问码**，勾选摘要发送确认后启用。

- 地址指向本仓库 Python 网关，不是小智的 WebSocket 地址，也不是智控台管理 API。
- 只发送本次问题、当前数据源的统计摘要；不自动上传原始记录、设备标识或历史对话。用户在问题里主动输入的内容也会发送。
- 设置和访问码仅保存在当前助手页面内存中，退出页面后需重新填写。可随时切回“本地摘要”。
- 网关 `mock` 模式的回答明确标记“尚未调用小智”；真正的小智模式需要服务端配置完成。请求失败会显示错误，不冒充本地或小智成功回答。
- 本轮只处理文字，不录音、不播放小智语音，不控制装置或修改记录。

启动与实机联调步骤见 [网关操作说明](../server/assistant-gateway/README.md)。只有 debug 构建可用 `127.0.0.1`、`localhost`、模拟器 `10.0.2.2` 的 HTTP；其他地址和 release 构建必须使用可信证书 HTTPS。

## 开发与构建

固定环境：Flutter **3.47.4** / Dart **3.13.3**、JDK **17**、Android compile/target SDK **36**，依赖见 `pubspec.lock`。配置好 Android SDK 与 `JAVA_HOME` 后：

```bash
cd mobile_app
flutter doctor -v
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

USB 安装需打开手机开发者选项 / USB 调试，并在手机上授权电脑。debug APK 为内部测试包。当前 Gradle 的 release 仍使用 debug 签名，**不能作为正式商店发布包**；正式分发前建立团队保管的发布密钥并配置签名。

可选 `--dart-define=ASSISTANT_GATEWAY_URL=https://your-host/v1/assistant/chat` 仅预填地址，不自动启用在线模式。不要用构建参数把 Token 或模型 API Key 写入 APK。

`flutter_reactive_ble 5.5.0` 子项目的 compileSdk 在 `android/build.gradle.kts` 调整为 36，以兼容当前 AndroidX；不修改本机 pub 缓存。升级插件和 Flutter 时复查该兼容配置。

## 代码入口与口径

| 位置 | 内容 |
|---|---|
| `lib/database/`、`lib/models/` | 正式事件模型、事务、去重、连续同步位置 |
| `lib/pages/`、`lib/services/` | 概览、历史、筛选、CSV、演示数据 |
| `lib/ble/` | 原型扫描/连接、分片校验、文本数据库、联调页 |
| `lib/assistant/` | 本地 / 在线 Provider、摘要、设置与聊天页面 |
| `test/` | 数据、协议、页面、权限状态、在线助手网络契约测试 |

统计中 `event_type=1` 为使用动作，`event_type=2` 单独统计；未知与未来时间不计入按日统计。日期筛选影响历史与 CSV，助手每次提问重新读取当前数据源的今日 / 近 7 天摘要。

电脑自动化测试不能替代 Android 权限弹窗、手机分享面板、BLE 射频与整机掉电验收。后续任务见 [Android 路线](../docs/android-roadmap.md)；历史 iOS 验证保留在 [归档说明](../docs/ios-readiness.md)。
