import 'dart:async';

import 'package:flutter/material.dart';

import 'ble_service.dart';

class BleStatusPage extends StatefulWidget {
  const BleStatusPage({
    super.key,
    BleService? service,
  }) : _service = service;

  final BleService? _service;

  @override
  State<BleStatusPage> createState() => _BleStatusPageState();
}

class _BleStatusPageState extends State<BleStatusPage> {
  late final BleService _bleService = widget._service ?? BleService();
  late final bool _ownsBleService = widget._service == null;

  late final StreamSubscription<List<BleDeviceInfo>> _deviceSubscription;
  late final StreamSubscription<BleConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _messageSubscription;

  List<BleDeviceInfo> _devices = const <BleDeviceInfo>[];
  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  final List<String> _messages = <String>[];

  @override
  void initState() {
    super.initState();
    _devices = _bleService.devices;
    _status = _bleService.status;

    _deviceSubscription = _bleService.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() => _devices = devices);
    });

    _statusSubscription = _bleService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });

    _messageSubscription = _bleService.rawTextStream.listen((message) {
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        if (_messages.length > 40) {
          _messages.removeRange(0, _messages.length - 40);
        }
      });
      if (message.startsWith('扫描到新设备')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });

    unawaited(_bleService.initializeAutoScan());
  }

  @override
  void dispose() {
    _deviceSubscription.cancel();
    _statusSubscription.cancel();
    _messageSubscription.cancel();
    if (_ownsBleService) {
      _bleService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _status.name[0].toUpperCase() + _status.name.substring(1);
    final hasActiveConnection = _status == BleConnectionStatus.connecting ||
        _status == BleConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Prototype v0')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'BLE 原型连接状态',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('状态：'),
                        Chip(
                          label: Text(statusLabel),
                          backgroundColor: _statusColor(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('断线后自动重连'),
                      value: _bleService.autoReconnectEnabled,
                      onChanged: (value) {
                        setState(() {
                          _bleService.setAutoReconnect(value);
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('进入 App 后自动扫描'),
                      value: _bleService.autoScanEnabled,
                      onChanged: (value) {
                        setState(() {
                          _bleService.setAutoScan(value);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _status == BleConnectionStatus.connecting ||
                          _status == BleConnectionStatus.connected
                      ? null
                      : () => _bleService.startScan(),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('扫描设备'),
                ),
                OutlinedButton.icon(
                  onPressed: hasActiveConnection
                      ? () => _bleService.disconnect()
                      : () => _bleService.cancelScan(),
                  icon: Icon(
                    hasActiveConnection
                        ? Icons.bluetooth_disabled
                        : Icons.stop_circle_outlined,
                  ),
                  label: Text(hasActiveConnection ? '断开连接' : '取消扫描'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '已发现设备',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (_devices.isEmpty)
                        const Text('暂无设备，点击“扫描设备”开始搜索。')
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: _devices.length,
                            itemBuilder: (context, index) {
                              final device = _devices[index];
                              return ListTile(
                                title: Text(device.name),
                                subtitle: Text(device.id),
                                trailing: Text('${device.rssi} dBm'),
                                onTap: () => _bleService.connectToDevice(device.id),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '原始Notify文本',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _messages.isEmpty
                            ? const Center(
                                child: Text('还没有收到设备数据。'),
                              )
                            : ListView.builder(
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SelectableText(_messages[index]),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor() {
    switch (_status) {
      case BleConnectionStatus.connected:
        return Colors.green.shade100;
      case BleConnectionStatus.connecting:
      case BleConnectionStatus.scanning:
        return Colors.orange.shade100;
      case BleConnectionStatus.error:
        return Colors.red.shade100;
      case BleConnectionStatus.disconnected:
      default:
        return Colors.grey.shade200;
    }
  }
}
