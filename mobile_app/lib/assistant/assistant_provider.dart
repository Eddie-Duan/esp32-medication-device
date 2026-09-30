import 'models/assistant_context.dart';

/// 一轮历史对话，供多轮上下文使用。`role` 只取 `user` / `assistant`。
///
/// 不用页面里的 `ChatMessage`：那里面还带着来源、时间戳、分隔提示这些 UI 概念，
/// provider 只需要「谁说了什么」这两个字段，传得越少越好。
typedef ChatTurn = ({String role, String text});

/// AI 服务的统一接口。
///
/// 第一阶段使用 MockAssistantProvider；后续可以增加 HTTP/WebSocket
/// Provider，而不需要修改页面和同步逻辑。
abstract class AssistantProvider {
  Future<String> reply({
    required String question,
    required AssistantContext context,
    List<String> references = const [],
  });
}

/// 支持增量流式输出的在线 provider（目前只有直连用户模型的实现）。
///
/// [reply] 仍返回整段回答；页面在「在线 + 支持流式」时改用 [replyStream]，
/// 让回答边出边显示，而不是等整段拼完才一起冒出来。网关是历史实现，
/// 不支持流式，也不支持多轮上下文，所以 [history] 只在这里出现。
abstract class StreamingAssistantProvider implements AssistantProvider {
  Stream<String> replyStream({
    required String question,
    required AssistantContext context,
    List<String> references = const [],
    List<ChatTurn> history = const [],
  });
}
