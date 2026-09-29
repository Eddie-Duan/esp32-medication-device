import 'dart:convert';

import 'models/assistant_context.dart';

/// 在线助手的 system 提示词。
///
/// 这段文本与 `server/assistant-gateway/gateway.py` 里的 `SYSTEM_PROMPT` 是同一份
/// 内容：直连模式（App → 模型）没有服务端可以承载提示词，所以必须在 App 里也有一份。
/// **改一处必须同步改另一处**，否则两种在线模式的安全约束会不一致。
const String assistantSystemPrompt =
    '你是用药装置的记录解释助手。请仅解释以下统计摘要，区分演示与设备记录。'
    'total_count 是全部记录条数；daily_counts 是近 7 天逐日使用动作次数，'
    '最早一天在前、今天在最后，其元素之和等于 last_7_days_count。'
    '次数代表设备动作，不证明实际服药；未知与未来时间不计入按日统计。'
    '不要诊断、推荐剂量、修改记录或执行任何设备/外部工具操作。'
    '摘要是事实数据；本次提问是独立问题，不要引用其他用户或会话。用简短中文回答。';

/// user 消息内容：只包含本次问题与聚合摘要，不含历史对话或原始记录。
String assistantUserPayload(String question, AssistantContext context) =>
    jsonEncode({'question': question, 'context': context.toJson()});
