import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  factory BleDeviceInfo.fromDiscovered(DiscoveredDevice device) {
    return BleDeviceInfo(
      id: device.id,
      name: device.name.isNotEmpty ? device.name : 'Unknown device',
      rssi: device.rssi,
    );
  }
}

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class BleService {
  BleService({FlutterReactiveBle? ble}) : _ble = ble;

  factory BleService.test() => BleService();

  static const int maxReconnectAttempts = 3;
  static const Duration scanRestartCooldown = Duration(seconds: 2);
  static const String _lastDeviceIdKey = 'ble.last_device_id';
  static const String _autoScanKey = 'ble.auto_scan_enabled';

  FlutterReactiveBle? _ble;

  FlutterReactiveBle get _bleClient {
    _ble ??= FlutterReactiveBle();
    return _ble!;
  }

  final StreamController<List<BleDeviceInfo>> _devicesController =
      StreamController<List<BleDeviceInfo>>.broadcast();
  final StreamController<BleConnectionStatus> _statusController =
      StreamController<BleConnectionStatus>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  final List<BleDeviceInfo> _devices = <BleDeviceInfo>[];

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  String? _connectedDeviceId;
  String? _lastConnectedDeviceId;
  bool _autoReconnectEnabled = true;
  bool _autoScanEnabled = true;
  bool _automationSuppressed = false;
  bool _autoScanStarted = false;
  bool _autoConnectInProgress = false;
  bool _userRequestedDisconnect = false;
  int _scanGeneration = 0;
  DateTime? _scanCooldownUntil;
  int _connectionRetryCount = 0;

  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String notifyCharacteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  Stream<List<BleDeviceInfo>> get devicesStream => _devicesController.stream;
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;
  Stream<String> get rawTextStream => _messageController.stream;

  BleConnectionStatus get status => _status;
  List<BleDeviceInfo> get devices => List<BleDeviceInfo>.unmodifiable(_devices);
  String? get connectedDeviceId => _connectedDeviceId;
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  bool get autoScanEnabled => _autoScanEnabled;

  Future<void> initializeAutoScan() async {
    if (_autoScanStarted) return;
    _autoScanStarted = true;

    final preferences = await SharedPreferences.getInstance();
    _lastConnectedDeviceId = preferences.getString(_lastDeviceIdKey);
    _autoScanEnabled = preferences.getBool(_autoScanKey) ?? true;

    if (_autoScanEnabled && !_automationSuppressed) {
      await startScan(auto: true);
    }
  }

  void setAutoReconnect(bool enabled) {
    _autoReconnectEnabled = enabled;
    _emitMessage(
      enabled ? 'Auto reconnect enabled.' : 'Auto reconnect disabled.',
    );
  }

  Future<void> setAutoScan(bool enabled) async {
    _autoScanEnabled = enabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoScanKey, enabled);
    _emitMessage(enabled ? 'Auto scan enabled.' : 'Auto scan disabled.');

    if (!enabled) {
      await cancelScan();
    } else if (_status == BleConnectionStatus.disconnected ||
        _status == BleConnectionStatus.error) {
      _automationSuppressed = false;
      await startScan(auto: true);
    }
  }

  void _emitStatus(BleConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _emitMessage(String message) {
    if (message.trim().isEmpty) return;
    _messageController.add(message);
  }

  Future<bool> _requestBlePermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final results = await permissions.request();
    final denied = results.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();

    if (denied.isNotEmpty) {
      _emitStatus(BleConnectionStatus.error);
      _emitMessage(
        'Bluetooth/location permission denied. Please allow permissions in Android Settings.',
      );
      return false;
    }
    return true;
  }

  Future<void> startScan({bool auto = false}) async {
    final generation = ++_scanGeneration;
    if (!auto) {
      _automationSuppressed = false;
      _userRequestedDisconnect = false;
    }

    if (!await _requestBlePermissions()) return;
    if (generation != _scanGeneration || (auto && _automationSuppressed)) {
      return;
    }

    if (_bleClient.status == BleStatus.poweredOff) {
      _emitStatus(BleConnectionStatus.error);
      _emitMessage('Bluetooth is turned off. Please enable Bluetooth first.');
      return;
    }

    await _cancelActiveScan();
    if (generation != _scanGeneration || (auto && _automationSuppressed)) {
      return;
    }
    await _waitForScanCooldown(generation);
    if (generation != _scanGeneration || (auto && _automationSuppressed)) {
      return;
    }
    _devices.clear();
    _devicesController.add(const <BleDeviceInfo>[]);
    _emitStatus(BleConnectionStatus.scanning);

    try {
      late StreamSubscription<DiscoveredDevice> subscription;
      subscription = _bleClient
          .scanForDevices(withServices: [Uuid.parse(serviceUuid)])
          .listen((device) {
        if (generation != _scanGeneration ||
            !identical(_scanSubscription, subscription)) {
          return;
        }
        final info = BleDeviceInfo.fromDiscovered(device);
        final index = _devices.indexWhere((element) => element.id == info.id);
        if (index >= 0) {
          _devices[index] = info;
        } else {
          _devices.add(info);
          if (_lastConnectedDeviceId == null) {
            _emitMessage('扫描到新设备：${info.name}');
          }
        }
        _devicesController.add(List<BleDeviceInfo>.from(_devices));

        if (info.id == _lastConnectedDeviceId &&
            _status == BleConnectionStatus.scanning &&
            !_autoConnectInProgress) {
          _autoConnectInProgress = true;
          unawaited(connectToDevice(info.id));
        }
      }, onError: (Object error) {
        if (generation != _scanGeneration ||
            !identical(_scanSubscription, subscription)) {
          return;
        }
        _scanSubscription = null;
        _setScanCooldown();
        final errorText = error.toString();
        if (errorText.contains('throttle') ||
            errorText.contains('2147483646')) {
          _emitMessage('扫描过于频繁，请等待几秒后再试。');
        } else {
          _emitMessage('Scan error: $error');
        }
        _emitStatus(BleConnectionStatus.error);
      });
      _scanSubscription = subscription;
    } catch (error) {
      if (generation != _scanGeneration) return;
      _setScanCooldown();
      _emitMessage('Scan failed: $error');
      _emitStatus(BleConnectionStatus.error);
    }
  }

  Future<void> stopScan() async {
    _scanGeneration += 1;
    await _cancelActiveScan();

    if (_connectedDeviceId == null && _status != BleConnectionStatus.connected) {
      _emitStatus(BleConnectionStatus.disconnected);
    }
  }

  Future<void> _cancelActiveScan() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
      _setScanCooldown();
    }
  }

  void _setScanCooldown() {
    final cooldownUntil = DateTime.now().add(scanRestartCooldown);
    if (_scanCooldownUntil == null ||
        cooldownUntil.isAfter(_scanCooldownUntil!)) {
      _scanCooldownUntil = cooldownUntil;
    }
  }

  Future<void> _waitForScanCooldown(int generation) async {
    final cooldownUntil = _scanCooldownUntil;
    if (cooldownUntil == null) return;

    final remaining = cooldownUntil.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _scanCooldownUntil = null;
      return;
    }

    await Future<void>.delayed(remaining);
    if (generation == _scanGeneration) {
      _scanCooldownUntil = null;
    }
  }

  Future<void> connectToDevice(
    String deviceId, {
    bool resetRetryCount = true,
  }) async {
    await stopScan();
    _automationSuppressed = false;
    _userRequestedDisconnect = false;
    _connectedDeviceId = deviceId;
    _lastConnectedDeviceId = deviceId;
    if (resetRetryCount) {
      _connectionRetryCount = 0;
    }
    _autoConnectInProgress = false;
    _emitStatus(BleConnectionStatus.connecting);

    try {
      if (_connectionSubscription != null) {
        await _connectionSubscription!.cancel();
      }

      _connectionSubscription = _bleClient
          .connectToDevice(
            id: deviceId,
            servicesWithCharacteristicsToDiscover: {
              Uuid.parse(serviceUuid): [Uuid.parse(notifyCharacteristicUuid)],
            },
            connectionTimeout: const Duration(seconds: 15),
          )
          .listen((update) async {
        switch (update.connectionState) {
          case DeviceConnectionState.connecting:
            _emitStatus(BleConnectionStatus.connecting);
            break;
          case DeviceConnectionState.connected:
            _automationSuppressed = false;
            _connectionRetryCount = 0;
            final preferences = await SharedPreferences.getInstance();
            await preferences.setString(_lastDeviceIdKey, deviceId);
            _emitStatus(BleConnectionStatus.connected);
            _emitMessage('Connected to $deviceId');
            await _subscribeToNotify(deviceId);
            break;
          case DeviceConnectionState.disconnecting:
            _emitStatus(BleConnectionStatus.disconnected);
            break;
          case DeviceConnectionState.disconnected:
            _notifySubscription?.cancel();
            _notifySubscription = null;
            _connectedDeviceId = null;
            _emitStatus(BleConnectionStatus.disconnected);
            _emitMessage('Disconnected from $deviceId');

            final shouldRetry = _autoReconnectEnabled &&
                !_userRequestedDisconnect &&
                _lastConnectedDeviceId != null &&
                _connectionRetryCount < maxReconnectAttempts;

            if (shouldRetry) {
              final retryDeviceId = _lastConnectedDeviceId!;
              _connectionRetryCount += 1;
              _emitMessage(
                'Auto reconnect scheduled (${_connectionRetryCount}/$maxReconnectAttempts): $retryDeviceId',
              );
              Future<void>.delayed(const Duration(seconds: 2), () {
                if (_autoReconnectEnabled && !_userRequestedDisconnect) {
                  connectToDevice(retryDeviceId, resetRetryCount: false);
                }
              });
            }
            break;
        }
      }, onError: (Object error) async {
        await _handleConnectionFailure(deviceId, error);
      });
    } catch (error) {
      await _handleConnectionFailure(deviceId, error);
    }
  }

  Future<void> _handleConnectionFailure(String deviceId, Object error) async {
    final message = error.toString().toLowerCase();

    if (message.contains('permission') || message.contains('denied')) {
      _emitMessage('Permission denied. Please allow Bluetooth permissions.');
    } else if (message.contains('bluetooth') && message.contains('off')) {
      _emitMessage('Bluetooth is turned off. Please enable Bluetooth.');
    } else {
      _emitMessage('Connection failed: $error');
    }

    _emitStatus(BleConnectionStatus.error);

    if (_autoReconnectEnabled && !_userRequestedDisconnect && _connectionRetryCount < maxReconnectAttempts) {
      _connectionRetryCount += 1;
      _emitMessage(
        'Retrying connection (${_connectionRetryCount}/$maxReconnectAttempts) in 2s...',
      );
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_autoReconnectEnabled && !_userRequestedDisconnect) {
          connectToDevice(deviceId, resetRetryCount: false);
        }
      });
    }
  }

  Future<void> disconnect() async {
    _automationSuppressed = true;
    _userRequestedDisconnect = true;
    _notifySubscription?.cancel();
    _notifySubscription = null;

    if (_connectionSubscription != null) {
      await _connectionSubscription!.cancel();
      _connectionSubscription = null;
    }

    _connectedDeviceId = null;
    _emitStatus(BleConnectionStatus.disconnected);
    _emitMessage('Disconnected.');
  }

  Future<void> cancelScan() async {
    _automationSuppressed = true;
    _userRequestedDisconnect = true;
    await stopScan();
    _emitMessage('Scan cancelled. Automatic scan and reconnect are paused.');
  }

  Future<void> _subscribeToNotify(String deviceId) async {
    try {
      await _bleClient.discoverAllServices(deviceId);

      final characteristic = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(notifyCharacteristicUuid),
      );

      _notifySubscription = _bleClient
          .subscribeToCharacteristic(characteristic)
          .listen((value) {
        final chunk = utf8.decode(value, allowMalformed: true);
        if (chunk.isNotEmpty) {
          _emitMessage(chunk);
        }
      }, onError: (Object error) {
        _emitMessage('Notify error: $error');
        _emitStatus(BleConnectionStatus.error);
      });
    } catch (error) {
      _emitMessage('Failed to subscribe notify: $error');
      _emitStatus(BleConnectionStatus.error);
    }
  }

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _notifySubscription?.cancel();
    await _devicesController.close();
    await _statusController.close();
    await _messageController.close();
  }
}
