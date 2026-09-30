import 'answer_verification.dart';
import 'assistant_knowledge.dart';
import 'assistant_provider.dart';
import 'models/assistant_context.dart';
import 'models/chat_message.dart';
import 'providers/mock_assistant_provider.dart';

class AssistantService {
  AssistantService({
    AssistantProvider? provider,
    this.isRemote = false,
    DateTime? now,
  })  : _provider = provider ?? MockAssistantProvider(),
        // 命名参数不能叫 `_now`，只能用公开名 `now` 显式赋值；同 ble_service.dart。
        _now = now; // ignore: prefer_initializing_formals

  final AssistantProvider _provider;
  final bool isRemote;

  /// 注入固定时间便于测试；本地规则自己会读当前时间，这里只有回验需要它。
  final DateTime? _now;

  Future<ChatMessage> ask({
    required String question,
    required AssistantContext context,
  }) async {
    // 只有在线模式检索设备知识库：本地规则不联网、也不看这份语料。
    final chunks = isRemote ? retrieveKnowledge(question) : const <KnowledgeChunk>[];
    final references = [for (final chunk in chunks) chunk.toReference()];
    // 检索到的知识里出现过的数字要放行进回验，见 answer_verification.dart。
    final referenceNumbers = <int>{
      for (final chunk in chunks) ...[
        ...numbersInText(chunk.title),
        ...numbersInText(chunk.body),
      ],
    };

    final answer = await _provider.reply(
      question: question,
      context: context,
      references: references,
    );
    if (!isRemote) {
      // 本地回答就是由同一份摘要算出来的，不存在编造，也没有来源标记可拆。
      return ChatMessage(
        role: ChatRole.assistant,
        text: answer,
        createdAt: DateTime.now(),
        source: ChatSource.local,
      );
    }

    final parsed = parseRemoteAnswer(answer);
    if (parsed.isKnowledge) {
      // 通用知识回答不参与数字回验：里面的数字（例如「全球约 3 亿人」）本来就不
      // 来自摘要，拿摘要去比对只会把正常回答误判成编造，还得跟一句莫名其妙的提醒。
      return ChatMessage(
        role: ChatRole.assistant,
        text: '${parsed.body}\n\n$remoteKnowledgeNote',
        createdAt: DateTime.now(),
        source: ChatSource.knowledge,
      );
    }
    return ChatMessage(
      role: ChatRole.assistant,
      // 只有用到记录的联网回答需要回验。
      text: verifyRemoteAnswer(
        parsed.body,
        context,
        now: _now,
        extra: referenceNumbers,
      ),
      createdAt: DateTime.now(),
      source: ChatSource.online,
    );
  }
}
