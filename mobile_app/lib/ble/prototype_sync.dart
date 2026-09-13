import 'prototype_protocol.dart';
import 'prototype_store.dart';

/// Transport-independent, serialized by BleService. Writes ACK only after the
/// SQLite transaction finishes. A reconnect uses a new token and resends files.
class PrototypeSync {
  PrototypeSync({
    required this.deviceId,
    required this.token,
    required this.store,
    required this.write,
    required this.isActive,
  });
  final String deviceId;
  final String token;
  final PrototypeStore store;
  final Future<void> Function(String command) write;
  final bool Function() isActive;
  int? expectedCount;
  final Map<int, String> _saved = {};
  final Set<String> _fileIds = {};
  bool endReceived = false;
  bool completed = false;
  int get savedCount => _saved.length;

  Future<void> accept(List<String> fields) async {
    if (!isActive() || fields.length < 2 || fields[1] != token) return;
    switch (fields[0]) {
      case 'BEGIN':
        if (fields.length != 3) throw const FormatException('BEGIN 格式错误');
        final count = int.parse(fields[2]);
        if (count < 0 ||
            count > 256 ||
            (expectedCount != null && expectedCount != count)) {
          throw const FormatException('记录数量不一致或超过原型上限');
        }
        expectedCount = count;
        await write('START|$token');
      case 'R':
        if (fields.length != 5 || expectedCount == null || completed) {
          throw const FormatException('记录在 BEGIN 之前或格式错误');
        }
        final index = int.parse(fields[2]);
        final file = fields[3];
        final raw = fields[4];
        if (index < 0 ||
            index >= expectedCount! ||
            index > _saved.length ||
            !RegExp(r'^data_[A-Za-z0-9_.-]{1,80}\.txt$').hasMatch(file) ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$').hasMatch(raw)) {
          throw const FormatException('记录序号、文件名或时间文本无效');
        }
        final payload = '$file|$raw';
        if ((_saved.containsKey(index) && _saved[index] != payload) ||
            (!_saved.containsKey(index) && _fileIds.contains(file))) {
          throw const FormatException('重传内容不一致或文件重复');
        }
        await store.save(
          PrototypeRecord(
            deviceId: deviceId,
            fileId: file,
            rawText: raw,
            receivedAt: DateTime.now(),
          ),
        );
        if (!isActive()) return;
        _saved[index] = payload;
        _fileIds.add(file);
        await write('ACK|$token|$index');
      case 'END':
        if (fields.length != 3 ||
            expectedCount == null ||
            int.parse(fields[2]) != expectedCount ||
            _saved.length != expectedCount) {
          throw const FormatException('记录未完整保存，不发送 COMMIT');
        }
        endReceived = true;
        await write('COMMIT|$token');
      case 'DONE':
        if (fields.length != 2 || !endReceived) {
          throw const FormatException('未完成接收就收到 DONE');
        }
        completed = true;
      case 'ERROR':
        throw StateError('设备同步错误：${fields.skip(2).join(' ')}');
      default:
        throw const FormatException('未知的原型帧类型');
    }
  }
}
