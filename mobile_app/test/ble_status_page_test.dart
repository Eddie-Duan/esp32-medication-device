import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/ble/ble_service.dart';
import 'package:medication_device_app/ble/ble_status_page.dart';

void main() {
  testWidgets('BLE status page renders prototype title and disconnected state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BleStatusPage(service: BleService.test()),
      ),
    );

    expect(find.text('Prototype v0'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
  });
}
