import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/ble/ble_service.dart';
import 'package:medication_device_app/ble/ble_status_page.dart';
import 'package:medication_device_app/main.dart';
import 'package:medication_device_app/models/medication_record.dart';
import 'package:medication_device_app/services/record_controller.dart';
import 'widget_test.dart' show MemoryRecords;

void main() {
  testWidgets('A demo navigation keeps B accessible and passes only the device repository', (tester) async {
    final device = MemoryRecords(RecordSource.device);
    final demo = MemoryRecords(RecordSource.demo);
    final controller = RecordController(deviceRepository: device, demoRepository: demo);
    final ble = BleService.test();
    addTearDown(() async {
      ble.dispose(); controller.dispose();
      await device.close(); await demo.close();
    });
    await controller.importDemo();
    await tester.pumpWidget(MedicationDeviceApp(controller: controller,
      connectionBuilder: (_, repository) {
        expect(identical(repository, device), true);
        return BleConnectionCard(service: ble);
      }));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(BleConnectionCard), 200,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(BleConnectionCard));
    await tester.pumpAndSettle();
    expect(find.text('设备连接与原型数据'), findsOneWidget);
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录').last); await tester.pumpAndSettle();
    expect(controller.source, RecordSource.demo);
    expect(controller.records, hasLength(11));
    expect(await device.readAll(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
