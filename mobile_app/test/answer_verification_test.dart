import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/answer_verification.dart';
import 'package:medication_device_app/assistant/assistant_provider.dart';
import 'package:medication_device_app/assistant/assistant_service.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';

class _FixedProvider implements AssistantProvider {
  _FixedProvider(this.answer);

  final String answer;

  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
  }) async => answer;
}

void main() {
  // Fixed local clock so the rule engine's derived numbers are deterministic.
  final now = DateTime(2026, 9, 29, 10);

  const context = AssistantContext(
    todayCount: 2,
    last7DaysCount: 8,
    invalidEventCount: 1,
    unknownTimeCount: 1,
    totalCount: 21,
    dailyCounts: [0, 1, 0, 2, 0, 0, 5],
  );

  test('回答只用摘要里出现过的数字时不报警', () {
    expect(
      numbersNotInSummary(
        '今天使用 2 次，近 7 天共 8 次，逐日（最早在前）0、1、0、2、0、0、5，共 21 条记录。',
        context,
        now: now,
      ),
      isEmpty,
    );
  });

  test('凭空出现的次数会被指出', () {
    expect(
      numbersNotInSummary('本周记录了 12 次使用动作。', context, now: now),
      [12],
    );
  });

  test('复述最后同步时间不会被当成编造', () {
    final withSync = AssistantContext(
      todayCount: 1,
      last7DaysCount: 1,
      totalCount: 1,
      dailyCounts: const [0, 0, 0, 0, 0, 0, 1],
      lastSyncAt: DateTime(2026, 9, 29, 8, 30),
    );
    expect(
      numbersNotInSummary(
        '最后同步于 ${withSync.lastSyncAt!.toLocal()}，共 1 条记录。',
        withSync,
        now: now,
      ),
      isEmpty,
    );
  });

  test('规则引擎算出来的派生数字可以被复述', () {
    // daily_counts 里有 5 天是 0，blank_days 会说「近 7 天中有 5 天没有设备记录」。
    // 5 是算出来的结论，模型复述它不算编造，否则每次都会误报。
    const derived = AssistantContext(
      todayCount: 0,
      last7DaysCount: 2,
      totalCount: 5,
      dailyCounts: [0, 1, 0, 0, 1, 0, 0],
    );
    expect(
      numbersNotInSummary('近 7 天有 5 天没有设备记录，且已连续 2 天没有记录。', derived, now: now),
      isEmpty,
    );
  });

  test('多个可疑数字去重后升序返回', () {
    expect(
      numbersNotInSummary('共 30 次，另有 12 条异常，30 次里包含 12 条。', context, now: now),
      [12, 30],
    );
  });

  test('回验只追加提醒，不改动回答本身', () {
    final verified = verifyRemoteAnswer('本周记录了 12 次。', context, now: now);
    expect(verified, startsWith('本周记录了 12 次。'));
    expect(verified, contains('12'));
    expect(verified, contains('与当前统计摘要对不上'));
    expect(mismatchNotice(const []), isNull);
  });

  test('没有可疑数字时原文返回', () {
    expect(verifyRemoteAnswer('近 7 天共 8 次。', context, now: now), '近 7 天共 8 次。');
  });

  test('回验自身无法判断时放行，不阻断回答', () {
    // 超出 int 范围的长数字解析不出来；宁可放行，也不能让助手指望不上。
    const answer = '共 99999999999999999999 次。';
    expect(verifyRemoteAnswer(answer, const AssistantContext(), now: now), answer);
    expect(verifyRemoteAnswer('', const AssistantContext(), now: now), '');
  });

  test('只有在线回答会被回验，本地回答保持原样', () async {
    const bogus = '本周记录了 12 次使用动作。';
    final remote = await AssistantService(
      provider: _FixedProvider(bogus),
      isRemote: true,
      now: now,
    ).ask(question: '最近怎么样？', context: context);
    expect(remote.text, contains('与当前统计摘要对不上'));

    final local = await AssistantService(
      provider: _FixedProvider(bogus),
      now: now,
    ).ask(question: '最近怎么样？', context: context);
    expect(local.text, bogus);
  });
}
