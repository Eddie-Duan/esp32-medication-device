class AssistantContext {
  const AssistantContext({
    this.todayCount = 0,
    this.last7DaysCount = 0,
    this.invalidEventCount = 0,
    this.lastSyncAt,
    this.isDemo = false,
    this.unknownTimeCount = 0,
    this.futureTimeCount = 0,
    this.totalCount = 0,
    this.dailyCounts = const [0, 0, 0, 0, 0, 0, 0],
  }) : assert(dailyCounts.length == 7, 'dailyCounts 必须正好 7 天');

  final int todayCount;
  final int last7DaysCount;
  final int invalidEventCount;
  final DateTime? lastSyncAt;
  final bool isDemo;
  final int unknownTimeCount;
  final int futureTimeCount;

  /// 全部记录条数，包含时间未知与未来时间的记录。
  final int totalCount;

  /// 近 7 天逐日使用动作次数，最早一天在前、今天在最后。
  final List<int> dailyCounts;

  Map<String, dynamic> toJson() {
    return {
      'today_count': todayCount,
      'last_7_days_count': last7DaysCount,
      'invalid_event_count': invalidEventCount,
      'last_sync_at': lastSyncAt?.toUtc().toIso8601String(),
      'is_demo': isDemo,
      'unknown_time_count': unknownTimeCount,
      'future_time_count': futureTimeCount,
      'total_count': totalCount,
      'daily_counts': dailyCounts,
    };
  }

  String toPromptSummary() {
    final syncText = lastSyncAt == null
        ? '尚未同步'
        : '最后同步于 ${lastSyncAt!.toLocal()}';
    return '${isDemo ? '演示数据' : '设备记录'}：共 $totalCount 条记录，'
        '今天 $todayCount 次，近 7 天 $last7DaysCount 次，'
        '近 7 天疑似无效记录 $invalidEventCount 条，$syncText。'
        '时间未知 $unknownTimeCount 条、未来时间 $futureTimeCount 条不计入按日统计。'
        '近 7 天逐日次数（最早一天在前，今天在最后）：${dailyCounts.join('、')}。';
  }
}
