class AssistantContext {
  const AssistantContext({
    this.todayCount = 0,
    this.last7DaysCount = 0,
    this.invalidEventCount = 0,
    this.lastSyncAt,
    this.isDemo = false,
    this.unknownTimeCount = 0,
    this.futureTimeCount = 0,
  });

  final int todayCount;
  final int last7DaysCount;
  final int invalidEventCount;
  final DateTime? lastSyncAt;
  final bool isDemo;
  final int unknownTimeCount;
  final int futureTimeCount;

  Map<String, dynamic> toJson() {
    return {
      'today_count': todayCount,
      'last_7_days_count': last7DaysCount,
      'invalid_event_count': invalidEventCount,
      'last_sync_at': lastSyncAt?.toUtc().toIso8601String(),
      'is_demo': isDemo,
      'unknown_time_count': unknownTimeCount,
      'future_time_count': futureTimeCount,
    };
  }

  String toPromptSummary() {
    final syncText = lastSyncAt == null
        ? '尚未同步'
        : '最后同步于 ${lastSyncAt!.toLocal()}';
    return '${isDemo ? '演示数据' : '设备记录'}：今天 $todayCount 次，近 7 天 $last7DaysCount 次，'
        '近 7 天疑似无效记录 $invalidEventCount 条，$syncText。'
        '时间未知 $unknownTimeCount 条、未来时间 $futureTimeCount 条不计入按日统计。';
  }
}
