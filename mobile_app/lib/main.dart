import 'dart:async';

import 'package:flutter/material.dart';

import 'assistant/assistant_page.dart';
import 'ble/ble_service.dart';
import 'ble/ble_status_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final bleService = BleService();
  runApp(MedicationDeviceApp(bleService: bleService));
  unawaited(bleService.initializeAutoScan());
}

class MedicationDeviceApp extends StatelessWidget {
  const MedicationDeviceApp({
    super.key,
    required this.bleService,
  });

  final BleService bleService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Medication Device',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: HomePage(bleService: bleService),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.bleService,
  });

  final BleService bleService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 用药装置')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_searching, size: 64),
            const SizedBox(height: 16),
            const Text('Flutter App 第一阶段骨架'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BleStatusPage(service: bleService),
                  ),
                );
              },
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('扫描设备'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AssistantPage(),
                  ),
                );
              },
              icon: const Icon(Icons.chat),
              label: const Text('打开 AI 助手'),
            ),
          ],
        ),
      ),
    );
  }
}
