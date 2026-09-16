import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

enum BleHostPlatform { android, ios, unsupported }

class BleAccessException implements Exception {
  const BleAccessException(this.message, {this.canOpenSettings = false});
  final String message;
  final bool canOpenSettings;
  @override
  String toString() => message;
}

/// iOS permission comes from CoreBluetooth initialization, never Android's
/// runtime permissions or the Android-only SDK version MethodChannel.
class BleAccessGate {
  BleAccessGate({
    required this.platform,
    required this.requestAndroidPermissions,
    required this.currentStatus,
    required this.statusChanges,
    this.timeout = const Duration(seconds: 30),
  });
  final BleHostPlatform platform;
  final Future<bool> Function() requestAndroidPermissions;
  final BleStatus Function() currentStatus;
  final Stream<BleStatus> Function() statusChanges;
  final Duration timeout;

  Future<void> ensureReady() async {
    if (platform == BleHostPlatform.unsupported) {
      throw const BleAccessException('请使用支持蓝牙的 Android 手机或 iPhone');
    }
    if (platform == BleHostPlatform.android &&
        !await requestAndroidPermissions()) {
      throw const BleAccessException(
        '请允许蓝牙权限；Android 11 及以下还需要位置权限',
        canOpenSettings: true,
      );
    }
    var status = currentStatus();
    if (status == BleStatus.unknown) {
      try {
        status = await statusChanges()
            .firstWhere((s) => s != BleStatus.unknown)
            .timeout(timeout);
      } on TimeoutException {
        throw const BleAccessException('蓝牙尚未就绪。请处理系统授权提示，再点击扫描设备');
      }
    }
    if (status == BleStatus.ready) return;
    throw BleAccessException(switch (status) {
      BleStatus.poweredOff => '请在系统设置中打开蓝牙，再返回 App 扫描',
      BleStatus.unauthorized => '蓝牙权限未获允许，请打开应用设置后开启蓝牙权限',
      BleStatus.locationServicesDisabled => '旧版 Android 扫描需要打开系统位置信息',
      BleStatus.unsupported => '当前设备不支持 BLE；iOS 模拟器不能代替 iPhone 蓝牙联调',
      _ => '蓝牙尚未就绪，请稍后重试',
    }, canOpenSettings: status == BleStatus.unauthorized);
  }
}
