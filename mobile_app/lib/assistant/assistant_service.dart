import 'answer_verification.dart';
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
        _now = now;

  final AssistantProvider _provider;
  final bool isRemote;

  /// 注入固定时间便于测试；本地规则自己会读当前时间，这里只有回验需要它。
  final DateTime? _now;

  Future<ChatMessage> ask({
    required String question,
    required AssistantContext context,
  }) async {
    final answer = await _provider.reply(question: question, context: context);

    return ChatMessage(
      role: ChatRole.assistant,
      // 只有联网回答需要回验：本地回答就是由同一份摘要算出来的，不存在编造。
      text: isRemote ? verifyRemoteAnswer(answer, context, now: _now) : answer,
      createdAt: DateTime.now(),
    );
  }
}
