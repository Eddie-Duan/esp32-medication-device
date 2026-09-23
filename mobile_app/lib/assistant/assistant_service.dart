import 'assistant_provider.dart';
import 'models/assistant_context.dart';
import 'models/chat_message.dart';
import 'providers/mock_assistant_provider.dart';

class AssistantService {
  AssistantService({AssistantProvider? provider, this.isRemote = false})
    : _provider = provider ?? MockAssistantProvider();

  final AssistantProvider _provider;
  final bool isRemote;

  Future<ChatMessage> ask({
    required String question,
    required AssistantContext context,
  }) async {
    final answer = await _provider.reply(question: question, context: context);

    return ChatMessage(
      role: ChatRole.assistant,
      text: answer,
      createdAt: DateTime.now(),
    );
  }
}
