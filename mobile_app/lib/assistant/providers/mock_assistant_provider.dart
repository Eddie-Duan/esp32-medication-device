import '../assistant_provider.dart';
import '../models/assistant_context.dart';

/// 不依赖网络和 API Key 的确定性回答器，用于开发、演示和自动化测试。
class MockAssistantProvider implements AssistantProvider {
  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final normalizedQuestion = question.trim();
    final sourceText = context.isDemo ? '演示数据' : '设备记录';
    if (normalizedQuestion.isEmpty) {
      return '请先输入问题。';
    }

    if (normalizedQuestion.contains('今天') ||
        normalizedQuestion.contains('次数')) {
      return '根据当前$sourceText，今天使用 ${context.todayCount} 次，'
          '近 7 天共 ${context.last7DaysCount} 次。这里只统计设备记录的使用动作，不能据此确认实际服药。';
    }

    if (normalizedQuestion.contains('异常') ||
        normalizedQuestion.contains('无效')) {
      return context.invalidEventCount == 0
          ? '$sourceText近 7 天没有疑似无效记录。这个结果仅基于已有记录。'
          : '$sourceText近 7 天有 ${context.invalidEventCount} 条疑似无效记录，可在历史中查看原始信息。';
    }

    if (normalizedQuestion.contains('最近') ||
        normalizedQuestion.contains('一周')) {
      return '$sourceText近 7 天的使用动作有 ${context.last7DaysCount} 次，'
          '另有疑似无效事件 ${context.invalidEventCount} 条。'
          '时间未知或晚于当前时间的记录不计入按日统计。';
    }

    return '这是第一阶段 Mock 模式回答。当前记录摘要：${context.toPromptSummary()} '
        '后续接入 AI 网关后，将由真实 Provider 生成回答。';
  }
}
