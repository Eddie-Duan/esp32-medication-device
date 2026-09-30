/// 消息的作者。
///
/// `system` 不是模型说的话，而是 App 自己的分隔提示（例如「已切回本地摘要」）。
/// 有了它，切换上游时就不必清空对话——插一条提示即可，历史仍然属于用户。
enum ChatRole { user, assistant, system }

/// 助手回答的来源。
///
/// 同屏可能出现三种来源的回答，用户必须能分清哪句是谁说的：
/// - [local]：本地规则算出来的，只基于统计摘要；
/// - [online]：在线模型，且这轮回答用到了记录/统计；
/// - [knowledge]：在线模型的通用健康知识（例如某种疾病的常识），与设备记录无关。
enum ChatSource { local, online, knowledge }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.source,
  });

  final ChatRole role;
  final String text;
  final DateTime createdAt;

  /// 只有 `assistant` 角色会带上来源；用户提问与分隔提示为 null。
  final ChatSource? source;

  bool get isUser => role == ChatRole.user;

  /// 分隔提示，渲染成居中淡色小字而不是气泡。
  bool get isNotice => role == ChatRole.system;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'created_at': createdAt.toIso8601String(),
    'source': source?.name,
  };

  /// 解析一条存档消息；认不出来就返回 null，由调用方跳过。
  ///
  /// 存档可能来自旧版本或被人为改坏，所以每个字段都要能容忍缺失与类型不符：
  /// 宁可少显示一条，也不能让整段历史读不出来。
  static ChatMessage? fromJson(Object? data) {
    if (data is! Map) return null;
    final role = switch (data['role']) {
      'user' => ChatRole.user,
      'assistant' => ChatRole.assistant,
      'system' => ChatRole.system,
      _ => null,
    };
    final text = data['text'];
    if (role == null || text is! String || text.isEmpty) return null;
    final createdAt = data['created_at'];
    return ChatMessage(
      role: role,
      text: text,
      // 时间戳坏掉不该让整条历史读不出来，退回当前时间。
      createdAt: createdAt is String
          ? (DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateTime.now(),
      source: switch (data['source']) {
        'local' => ChatSource.local,
        'online' => ChatSource.online,
        'knowledge' => ChatSource.knowledge,
        _ => null,
      },
    );
  }
}
