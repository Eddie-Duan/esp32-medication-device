import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/record_repository.dart';
import '../models/medication_record.dart';
import '../models/record_filter.dart';
import '../models/record_summary.dart';
import 'demo_data_service.dart';

class RecordController extends ChangeNotifier {
  RecordController(
      {required this.deviceRepository,
      required this.demoRepository,
      DateTime Function()? clock})
      : clock = clock ?? DateTime.now {
    if (deviceRepository.source != RecordSource.device ||
        demoRepository.source != RecordSource.demo) {
      throw ArgumentError('Device and demo repositories must stay separate');
    }
    for (final repo in [deviceRepository, demoRepository]) {
      _subscriptions.add(repo.changes.listen((_) {
        if (repo.source == source) unawaited(refresh());
      }));
    }
  }

  final RecordRepository deviceRepository;
  final RecordRepository demoRepository;
  final DateTime Function() clock;
  final List<StreamSubscription<void>> _subscriptions = [];
  RecordSource source = RecordSource.device;
  RecordFilter filter = const RecordFilter();
  List<MedicationRecord> records = const [];
  RecordSummary? summary;
  bool loading = false;
  String? error;
  var _revision = 0;
  var _disposed = false;
  Future<void>? _latestRefresh;

  RecordRepository get repository =>
      source == RecordSource.device ? deviceRepository : demoRepository;
  List<MedicationRecord> get visibleRecords => records
      .where((record) => filter.accepts(record.timestamp))
      .toList(growable: false);

  Future<void> selectSource(RecordSource value) async {
    if (source == value) return;
    source = value;
    records = const [];
    summary = null;
    filter = const RecordFilter();
    await refresh();
  }

  void setFilter(RecordFilter value) {
    filter = value;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final revision = ++_revision;
    // The Future returned to callers also waits for a newer refresh triggered
    // by a repository event; awaiting import/source-switch must mean ready.
    final pending = Future<void>.microtask(() => _readSnapshot(revision));
    _latestRefresh = pending;
    return _waitForLatest(pending);
  }

  Future<void> _waitForLatest(Future<void> pending) async {
    while (true) {
      await pending;
      if (_disposed || identical(pending, _latestRefresh)) return;
      pending = _latestRefresh!;
    }
  }

  Future<void> _readSnapshot(int revision) async {
    if (_disposed || revision != _revision) return;
    final repo = repository;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await repo.readAll();
      final lastSync = await repo.lastSyncAt();
      if (_disposed || revision != _revision) return;
      records = List.unmodifiable(data);
      summary =
          RecordSummary.calculate(data, now: clock(), lastSyncAt: lastSync);
    } catch (_) {
      if (_disposed || revision != _revision) return;
      // Do not display/export stale data as a successful refresh.
      records = const [];
      summary = null;
      error = '暂时无法读取本地记录，请重试。';
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<int> importDemo() async {
    final count =
        await demoRepository.seedDemo(DemoDataService.create(clock()));
    if (source != RecordSource.demo) {
      await selectSource(RecordSource.demo);
    } else {
      await refresh();
    }
    return count;
  }

  Future<void> resetDemo() async {
    await demoRepository.clearDemo();
    if (source == RecordSource.demo) await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
