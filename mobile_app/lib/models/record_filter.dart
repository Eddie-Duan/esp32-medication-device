/// Local calendar dates, with an exclusive end. Unknown timestamps are never
/// assigned to a day; they can be included explicitly alongside a date range.
class RecordFilter {
  const RecordFilter(
      {this.start, this.endExclusive, this.includeUnknown = true});

  final DateTime? start;
  final DateTime? endExclusive;
  final bool includeUnknown;

  bool accepts(int timestamp) {
    if (timestamp == 0) return includeUnknown;
    final instant = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return (start == null || !instant.isBefore(start!)) &&
        (endExclusive == null || instant.isBefore(endExclusive!));
  }

  String get description {
    if (start == null && endExclusive == null) return '全部日期';
    final end = endExclusive;
    final lastDay =
        end == null ? null : DateTime(end.year, end.month, end.day - 1);
    return '${start == null ? '不限' : dateLabel(start!)} 至 '
        '${lastDay == null ? '不限' : dateLabel(lastDay)}';
  }
}

String dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String timeLabel(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
