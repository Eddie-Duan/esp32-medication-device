import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

const prototypeServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const prototypeCharacteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

abstract interface class BleTransport {
  Future<void> ensureReady();
  Stream<DiscoveredDevice> scan();
  Stream<ConnectionStateUpdate> connect(String deviceId);
  Future<void> discover(String deviceId);
  Stream<List<int>> subscribe(String deviceId);
  Future<void> write(String deviceId, List<int> bytes);
}

class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();
  final FlutterReactiveBle _ble;
  QualifiedCharacteristic _characteristic(String deviceId) =>
      QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(prototypeServiceUuid),
        characteristicId: Uuid.parse(prototypeCharacteristicUuid),
      );

  @override
  Future<void> ensureReady() async {
    if (Platform.isAndroid) {
      final sdk = await const MethodChannel(
        'org.igem.medication/platform',
      ).invokeMethod<int>('androidSdkInt');
      if (sdk == null) throw StateError('无法读取 Android 版本');
      final permissions = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final result = await permissions.request();
      if (result.values.any((value) => !value.isGranted)) {
        throw StateError('请在系统设置中允许蓝牙权限；Android 11 及以下还需要位置权限');
      }
    } else if (!Platform.isIOS) {
      throw UnsupportedError('蓝牙联调需要 Android 或 iOS 手机');
    }
    // CoreBluetooth on iOS prompts using NSBluetoothAlwaysUsageDescription.
    final status = _ble.status == BleStatus.unknown
        ? await _ble.statusStream
              .firstWhere((s) => s != BleStatus.unknown)
              .timeout(const Duration(seconds: 15))
        : _ble.status;
    if (status != BleStatus.ready) {
      throw StateError(switch (status) {
        BleStatus.poweredOff => '请先打开手机蓝牙',
        BleStatus.unauthorized => '请在系统设置中允许本 App 使用蓝牙',
        BleStatus.locationServicesDisabled => '旧版 Android 扫描需要打开系统位置信息',
        BleStatus.unsupported => '手机不支持 BLE',
        _ => '蓝牙尚未就绪，请稍后重试',
      });
    }
  }

  @override
  Stream<DiscoveredDevice> scan() =>
      _ble.scanForDevices(withServices: [Uuid.parse(prototypeServiceUuid)]);
  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) =>
      _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: const Duration(seconds: 15),
        servicesWithCharacteristicsToDiscover: {
          Uuid.parse(prototypeServiceUuid): [
            Uuid.parse(prototypeCharacteristicUuid),
          ],
        },
      );
  @override
  Future<void> discover(String deviceId) async {
    await _ble.discoverAllServices(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    final matches = services
        .where((s) => s.id == Uuid.parse(prototypeServiceUuid))
        .expand((s) => s.characteristics)
        .where((c) => c.id == Uuid.parse(prototypeCharacteristicUuid));
    if (matches.isEmpty ||
        !matches.first.isNotifiable ||
        !matches.first.isWritableWithResponse) {
      throw StateError('固件缺少原型 Write + Notify 特征，请刷入配套固件');
    }
  }

  @override
  Stream<List<int>> subscribe(String deviceId) =>
      _ble.subscribeToCharacteristic(_characteristic(deviceId));
  @override
  Future<void> write(String deviceId, List<int> bytes) => _ble
      .writeCharacteristicWithResponse(_characteristic(deviceId), value: bytes);
}
