# Prototype v0.1：C3 时间文本联调协议

此协议由本次 A+B 合并实现，配套 `firmware/esp32-c3/main/main.ino` 和 App 0.2.0。
它传输硬件启动/按键生成的原始时间文本，不等于 `data-format.md` 的正式事件协议。
原始文本保存在 `prototype_text.db`，不填写虚构的压力、置信度或事件类型，不计入 A 的正式事件统计。

## GATT 与组帧

Service：`4fafc201-1fb5-459e-8fcc-c5c9c331914b`。
Characteristic：`beb5483e-36e1-4688-b7f5-ea07361b26a8`，Read / Write With Response / Notify，CCCD `0x2902`。

每次 Notify 最多 20 字节，不依赖 MTU 协商。App 按字节缓存到 LF 再解码 UTF-8，最大一行 256 字节。
固件通知格式为 `LF + body + "|" + crc4 + LF`。前置 LF 能使重传从残缺帧恢复；空行忽略。
CRC-16/CCITT-FALSE：poly `0x1021`、init `0xffff`、refin/refout=false、xorout=0，覆盖 body 的 UTF-8 字节，不含末尾分隔符、校验值或 LF。crc4 为四位十六进制。独立标准校验向量 `123456789 → 29b1`。
App 发出的控制命令不带 LF，单次 Write With Response，最多 20 字节。

`token` 为 App 每轮随机生成的 8 位十六进制会话标识。设备 ID 为 12 位 eFuse 芯片标识（与手机系统给出的连接 ID 分开）。`index` 为本轮快照的零起始序号，不是正式事件序号。

| 方向 | body / 控制命令 | 行为 |
|---|---|---|
| App → 设备 | `HELLO` | 先建立 Notify 订阅，再发送；每秒重试，最多 6 次 |
| 设备 → App | `READY\|device_id\|P01` | 固件仅在 CCCD 已启用时发送；App 实际收到并校验才认为订阅就绪 |
| App → 设备 | `SYNC_REQ\|token` | 请求一个新的文件快照，取消旧轮次 |
| 设备 → App | `BEGIN\|token\|count` | 固定本轮文件总数；最多 256 个 |
| App → 设备 | `START\|token` | 已校验 BEGIN，可以发送第一条 |
| 设备 → App | `R\|token\|index\|file_id\|raw_text` | raw_text 为 `YYYY-MM-DD_HH-MM-SS`，file_id 不含目录前缀 |
| App → 设备 | `ACK\|token\|index` | 必须在 CRC 校验、字段检查及 SQLite 事务成功后发送；相同文件相同内容可以重发 ACK |
| 设备 → App | `END\|token\|count` | 本轮所有记录均已获 ACK |
| App → 设备 | `COMMIT\|token` | 已保存完整连续快照；本原型仅确认收齐，设备保留全部文件 |
| 设备 → App | `DONE\|token` | App 收到才显示本轮完成；重复 COMMIT 返回相同 DONE |
| 设备 → App | `ERROR\|token\|reason` | 显示设备错误，本轮停止，不清空文件 |

## 重试与数据保留

- BEGIN、R、END 均等待相应应用层回复；固件 1.5 秒超时重试，最多额外 3 次。超过次数发 `ACK_TIMEOUT`，保留文件。
- App 接收期间 12 秒无有效进展报超时；等待 DONE 时每 2 秒重发 COMMIT，最多额外 3 次。
- 坏 CRC 不 ACK，等待设备重发。序号不连续、文件内容冲突、存储失败均停止本轮，不 COMMIT。
- 同设备 `device_id + file_id` 是原型数据库主键；重传不增加数据，同键不同内容拒绝覆盖。
- 断线时清除当前会话，自动重连最多 3 次；用户主动断开/取消扫描会取消延迟重连。重连后重新同步全部保留文件，手机去重；这不是正式协议的游标续传。
- 新文件增加 Preferences 持久计数，防止同秒按键及重启后手动时钟重复造成覆盖。旧原型 `.txt` 仍可读取。
- 发送、断线和 COMMIT 都不调用 `SPIFFS.format()`。挂载使用 `SPIFFS.begin(false)`；挂载失败报告错误。
- 快照期间新增的按钮记录留待下一次点击“重新同步”。保留策略会占用设备容量，超过 256 个文件报告 `TOO_MANY_FILES`，后续需实现有确认边界的回收/分页。

## 当前边界

手动校时占位仍保留，文本中的时间不能解释为准确 UTC 或真实服药。正式 20 字节事件协议、传感器事件识别、正式游标及设备文件回收待继续开发；四特征 GATT 不会与本单特征原型混用。
