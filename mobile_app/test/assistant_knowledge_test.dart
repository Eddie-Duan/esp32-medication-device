import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/answer_verification.dart';
import 'package:medication_device_app/assistant/assistant_knowledge.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';

/// 知识库 `knowledge/README.md` 里的验收表，逐条对着检索结果验证。
void main() {
  test('空问题或无关问题检索不到任何一篇', () {
    expect(retrieveKnowledge(''), isEmpty);
    expect(retrieveKnowledge('   '), isEmpty);
    expect(retrieveKnowledge('今天天气怎么样'), isEmpty);
  });

  test('「设备能测出我吃了多少药吗」命中设备边界', () {
    final hits = retrieveKnowledge('设备能测出我吃了多少药吗');
    expect(hits.map((c) => c.id), contains('boundary.dose'));
  });

  test('「我上个月吃药规律吗」命中记录不代表服药', () {
    final hits = retrieveKnowledge('我上个月吃药规律吗');
    expect(hits.map((c) => c.id), contains('boundary.adherence'));
  });

  test('「同步提示 STORAGE_UNAVAILABLE 怎么办」命中对应错误码', () {
    final hits = retrieveKnowledge('同步提示 STORAGE_UNAVAILABLE 怎么办');
    expect(hits.map((c) => c.id), contains('sync.storage_unavailable'));
  });

  test('「我应该吃几片」不该由知识库回答——拒绝在提示词里，不在这里', () {
    // 剂量问题由 system 提示词的硬约束拒绝，知识库里不塞「拒绝」文案。
    expect(retrieveKnowledge('我应该吃几片'), isEmpty);
  });

  test('topK 截断且按相关度降序', () {
    final hits = retrieveKnowledge('设备能测出我吃了多少药吗', topK: 1);
    expect(hits, hasLength(1));
    expect(hits.first.id, 'boundary.dose');
  });

  test('toReference 拼成「标题：正文」的一行', () {
    final chunk = assistantKnowledge.firstWhere((c) => c.id == 'boundary.dose');
    expect(chunk.toReference(), '${chunk.title}：${chunk.body}');
  });

  test('知识里出现的数字放行进回验，不被误判成编造', () {
    final chunks = retrieveKnowledge('同步提示 TOO_MANY_FILES 怎么办');
    final extra = <int>{
      for (final chunk in chunks) ...[
        ...numbersInText(chunk.title),
        ...numbersInText(chunk.body),
      ],
    };
    const context = AssistantContext();
    const answer = '设备上的记录文件数量超过上限 256 个，需要先完成同步并提交回收。';

    // 不带知识里的数字：256 不在摘要允许集合里，会被提醒「对不上」。
    expect(verifyRemoteAnswer(answer, context), contains('对不上'));
    // 带上检索到知识里的数字：256 是权威事实，不再误报。
    expect(
      verifyRemoteAnswer(answer, context, extra: extra),
      isNot(contains('对不上')),
    );
  });
}
