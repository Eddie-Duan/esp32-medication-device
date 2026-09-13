import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/ble/ble_service.dart';
import 'package:medication_device_app/ble/ble_status_page.dart';

void main() {
  testWidgets(
    'BLE status page renders prototype title and disconnected state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BleStatusPage(service: BleService.test())),
      );

      expect(find.text('Prototype v0.1'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('已保存的原型文本'), 150);
      expect(tester.takeException(), isNull);
    },
  );
}
