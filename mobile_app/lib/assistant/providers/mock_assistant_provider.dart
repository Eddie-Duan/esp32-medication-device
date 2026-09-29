import '../assistant_provider.dart';
import '../models/assistant_context.dart';
import '../rules/observation_rules.dart';

/// App 侧的本地规则助手：不依赖网络和 API Key 的确定性回答器。
///
/// 它按固定规则解释统计摘要，并给出设备侧的维护提醒；
/// 不做诊断、不给剂量建议，也不把“没有设备记录”表述为“漏服”。
class MockAssistantProvider implements AssistantProvider {
  MockAssistantProvider({this.now});

  /// 注入固定时间便于测试；为空时每次提问读取当前本地时间。
  final DateTime? now;

  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      return '请先输入问题。';
    }

    final sourceText = context.isDemo ? '演示数据' : '设备记录';
    final observations =
        evaluateObservations(context, now: now ?? DateTime.now());
    final attention = _attentionNotes(observations);

    if (normalizedQuestion.contains('今天') ||
        normalizedQuestion.contains('次数')) {
      return '根据当前$sourceText，今天使用 ${context.todayCount} 次，'
          '近 7 天共 ${context.last7DaysCount} 次。这里只统计设备记录的使用动作，不能据此确认实际服药。'
          '$attention';
    }

    if (normalizedQuestion.contains('异常') ||
        normalizedQuestion.contains('无效')) {
      final base = context.invalidEventCount == 0
          ? '$sourceText近 7 天没有疑似无效记录。这个结果仅基于已有记录。'
          : '$sourceText近 7 天有 ${context.invalidEventCount} 条疑似无效记录，可在历史中查看原始信息。';
      return '$base$attention';
    }

    if (normalizedQuestion.contains('最近') ||
        normalizedQuestion.contains('一周') ||
        normalizedQuestion.contains('规律') ||
        normalizedQuestion.contains('波动') ||
        normalizedQuestion.contains('趋势')) {
      return '$sourceText近 7 天逐日使用动作（最早一天在前，今天在最后）：'
          '${context.dailyCounts.join('、')}，共 ${context.last7DaysCount} 次。'
          '时间未知或晚于当前时间的记录不计入按日统计。$attention';
    }

    if (normalizedQuestion.contains('建议') ||
        normalizedQuestion.contains('注意') ||
        normalizedQuestion.contains('怎么办')) {
      return '下面是按固定规则得出的观察，只陈述事实，不是医疗建议：\n'
          '${_observationList(observations)}'
          '设备动作次数只代表装置被使用，不能确认实际服药。';
    }

    return '当前记录摘要：${context.toPromptSummary()} '
        '本地助手按固定规则解释统计；可在右上角切换团队提供的在线助手。';
  }

  /// 只把需要用户采取动作的观察追加到具体回答之后。
  String _attentionNotes(List<AssistantObservation> observations) {
    final notes = observations
        .where((item) => item.level == ObservationLevel.attention)
        .map((item) => item.text)
        .toList();
    return notes.isEmpty ? '' : '\n需要留意：${notes.join(' ')}';
  }

  String _observationList(List<AssistantObservation> observations) {
    if (observations.isEmpty) {
      return '· 当前没有需要提醒的项目。\n';
    }
    return '${observations.map((item) => '· ${item.text}').join('\n')}\n';
  }
}
