import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/assistant_page.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';
import 'package:medication_device_app/database/record_repository.dart';
import 'package:medication_device_app/main.dart';
import 'package:medication_device_app/models/medication_record.dart';
import 'package:medication_device_app/pages/home_page.dart';
import 'package:medication_device_app/services/record_controller.dart';

/// UI fixture only. Real SQLite durability/transactions are exercised in
/// record_data_test.dart, rather than inferred from this in-memory fake.
class MemoryRecords implements RecordRepository {
  MemoryRecords(this.source);
  @override
  final RecordSource source;
  final rows = <MedicationRecord>[];
  final events = StreamController<void>.broadcast();
  bool failRead = false;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<List<MedicationRecord>> readAll() async {
    if (failRead) throw StateError('unavailable');
    return List.of(rows);
  }

  @override
  Future<DateTime?> lastSyncAt() async => null;
  @override
  Future<SaveRecordResult> saveValidatedRecord(MedicationRecord record) async {
    rows.add(record);
    events.add(null);
    return SaveRecordResult.inserted;
  }

  @override
  Future<int> seedDemo(List<MedicationRecord> records) async {
    if (rows.isNotEmpty) return 0;
    for (final record in records) {
      if (!rows.any((item) =>
          item.deviceId == record.deviceId && item.seq == record.seq)) {
        rows.add(record);
      }
    }
    events.add(null);
    return rows.length;
  }

  @override
  Future<void> clearDemo() async {
    rows.clear();
    events.add(null);
  }

  @override
  Future<int?> readSyncCursor(String deviceId) async => null;
  @override
  Future<void> advanceSyncCursor(String deviceId, int seq,
      {int? firstSequence}) async {}
  @override
  Future<void> markSyncCompleted(DateTime instant) async {}
  @override
  Future<void> close() async => events.close();
}

void main() {
  late MemoryRecords device;
  late MemoryRecords demo;
  late RecordController controller;
  setUp(() {
    device = MemoryRecords(RecordSource.device);
    demo = MemoryRecords(RecordSource.demo);
    controller = RecordController(
        deviceRepository: device,
        demoRepository: demo,
        clock: () => DateTime(2026, 9, 12, 12));
  });
  tearDown(() async {
    controller.dispose();
    await device.close();
    await demo.close();
  });

  testWidgets(
      'empty device view imports demo and changes back without polluting real records',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MedicationDeviceApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.summary!.total, 0);
    await tester.ensureVisible(find.text('载入演示数据'));
    await tester.tap(find.text('载入演示数据'));
    await tester.pumpAndSettle();
    expect(find.text('当前为演示数据，与设备记录分开保存。'), findsOneWidget);
    expect(controller.summary!.total, 11);
    expect(device.rows, isEmpty);
    await tester.tap(find.text('设备记录'));
    await tester.pumpAndSettle();
    expect(controller.summary!.total, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history date filter exports exactly the visible snapshot and source',
      (tester) async {
    await controller.importDemo();
    List<MedicationRecord>? exported;
    RecordSource? source;
    await tester.pumpWidget(MaterialApp(
        home: HomePage(
            controller: controller,
            exportRecords: (records, selectedSource, origin) async {
              exported = records;
              source = selectedSource;
              expect(origin.width, greaterThan(0));
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('当前显示 2 条 · CSV 导出相同记录'), findsOneWidget);
    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();
    expect(exported, hasLength(2));
    expect(source, RecordSource.demo);
    expect(exported!.every((record) => record.timestamp != 0), isTrue);
  });

  testWidgets(
      'assistant reloads context on each question instead of using fixed demo numbers',
      (tester) async {
    var loads = 0;
    await tester
        .pumpWidget(MaterialApp(home: AssistantPage(contextLoader: () async {
      loads++;
      return AssistantContext(
          todayCount: loads + 3, last7DaysCount: loads + 8, isDemo: true);
    })));
    await tester.tap(find.widgetWithText(ActionChip, '今天用了几次？'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今天使用 4 次'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '今天用了几次？'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今天使用 5 次'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('read errors offer retry and hide stale statistics',
      (tester) async {
    device.failRead = true;
    await tester.pumpWidget(MedicationDeviceApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取本地记录，请重试。'), findsOneWidget);
    expect(controller.summary, isNull);
    device.failRead = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(controller.summary!.total, 0);
    expect(find.text('让每次记录更清楚'), findsOneWidget);
  });

  testWidgets('compact and large-text layouts keep core controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.importDemo();
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: HomePage(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('历史记录').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
