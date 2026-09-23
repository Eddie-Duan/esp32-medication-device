# A+B 合并交付与周末联调

> 以下操作与原型限制仍可参考；版本号、35 项测试和编译记录属于当时的 0.2.0 交付。当前为 Android 0.3.0，小智文字网关已加入代码，最新任务与验证见 [Android 路线](android-roadmap.md)。本轮不再安排 iOS 验收。

本次合并 A 的 `fa7b067`（记录、SQLite、统计、CSV、助手与移动端工程）和 B 的 `e066047`（`ble_connect` 扫描、连接、自动重连），并修复两端原型同步。

## 已完成

- 一个 App 保留 A 的全部数据/演示页面，通过概览“设备连接”进入 B 的连接与原型文本页面。
- Android 12+ 申请蓝牙扫描/连接权限；旧 Android 申请位置权限。iOS 使用 CoreBluetooth 与现有蓝牙用途声明。
- 订阅后 HELLO/READY 握手，实际收到 READY 才请求同步；20 字节分片、换行缓存、CRC、保存后 ACK、完整接收后 COMMIT/DONE。
- 原型 SQLite 持久保存、重复去重、冲突拒绝；断线后重连重取、旧会话失效、手动停止取消重连。
- 固件不再发送后格式化，不在挂载失败时自动格式化；持久计数防止文件重名覆盖。
- 蓝牙服务由应用持有，退出连接页、查看 A 的历史/演示不会主动终止连接。

## 先交给硬件组

使用本分支 `firmware/esp32-c3/main/main.ino`，整套 components 一起更新。刷到 **ESP32-C3**，GPIO4 按钮接 GND，串口 115200。保持原板分区设置，不勾选整片擦除。

设备初始没有 SPIFFS 文件系统时会报告 `STORAGE_UNAVAILABLE`，应由硬件组确认板上无须保留数据并初始化 SPIFFS；不要为绕过错误恢复自动格式化。

## 手机操作

1. 安装 App 0.2.0 调试 APK，打开“用药装置”。包名沿用 A：`org.igem.medication.medication_device_app`。
2. B 旧包使用 `com.example.medication_device_app`，会作为另一应用存在；不要误开旧应用，也不要期待两包共享数据。A 旧版本同包名且签名一致时可覆盖升级。
3. ESP32 上电。App 概览点击“设备连接”→“扫描设备”→允许权限→选择 ESP32-C3。无需到系统蓝牙页配对。
4. 观察状态“等待订阅握手”→“正在接收并保存”→“原型文本已保存”。在下方查看原始时间文本。
5. 按硬件按钮生成新文件，点击 App“重新同步”；同一文件不会重复增加。关闭重开 App，已保存文本仍可查看。
6. A 的演示入口、历史、统计、CSV 和助手继续使用。原型时间文本在连接页查看，不会伪装成正式事件写入历史统计。

必须同时更新 APK 和固件。旧固件不识别 HELLO，仍可能在 App 订阅前发送并删除数据；只装新 APK 无法修复旧固件的删除逻辑。

## 联调记录（待填实测结果）

| 用例 | 通过标准 |
|---|---|
| 首次连接/订阅 | 收到 READY，之后才出现 SYNC_REQ |
| 重传 | 同一快照连续同步两次，原型保存条数不变 |
| 按键 | 按一下后再次同步，新增文件可见 |
| 断线 | 同步中断开，已保存数据保留；重连可取回未收齐部分 |
| 手动断开 | App 不在几秒后自动连回 |
| 持久化 | 关闭重开 App 后仍能读取时间文本与 A 的演示记录 |
| 错误 | 拒绝权限、关闭蓝牙、旧固件不握手时显示明确原因 |
| A 回归 | 演示导入、历史筛选、CSV 分享和助手仍可用 |

电脑自动化测试和 APK 构建不替代真机验收。Android/ESP32 联调待设备；iOS 工程与共用逻辑保留，但本次 Windows 环境不生成 IPA，也不代表通过 iPhone 测试。

本轮电脑验证：`flutter analyze` 无问题；35 项自动化测试通过；概览、蓝牙、历史和助手四张 Flutter 渲染预览通过。Arduino-ESP32 3.3.11 / `esp32:esp32:esp32c3` 编译通过，程序 691,693 字节、静态内存 18,508 字节。APK 为 0.2.0 (2) 内部调试包，仍使用 Android Debug 签名。

## 下一步开发

冻结正式 DeviceInfo、SyncStatus/SYNC_END、事件 CRC、序号重启规则后，把正式事件解码接入 A 的 `RecordRepository.saveValidatedRecord`；然后实现游标续传、按 COMMIT 范围回收、真实校时。小智语音与真实助手网关另行接入。

协议细节见 [Prototype v0.1](../protocol/prototype-text-v01.md)。权限实现参考 [Android 官方说明](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)，蓝牙操作参考 [flutter_reactive_ble 5.5.0](https://pub.dev/packages/flutter_reactive_ble/versions/5.5.0)。
