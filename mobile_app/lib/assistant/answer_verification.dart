import 'models/assistant_context.dart';
import 'rules/observation_rules.dart';

/// 在线回答结尾的来源标记，形如 `【来源】AI知识` / `【来源】记录统计`。
///
/// 只认**结尾**那一行：模型不一定听话，可能忘了写，也可能把标记写在正文中间，
/// 那种情况宁可当没写，也不能把正文从中间截断。
final RegExp _sourceMarker = RegExp(
  r'\n?[ \t　]*【来源】[ \t　]*[:：]?[ \t　]*(AI\s*知识|记录统计)[。.]?[ \t　]*$',
);

/// 通用知识回答末尾必须补的说明。
///
/// 这句话由 App 自己写，不采用模型那句：模型可能只写「我不是医生」这类模糊说法，
/// 也可能干脆不写。用户需要知道的是具体这一件事——**这条信息不是来自你的设备记录**。
const remoteKnowledgeNote =
    '（以上是 AI 的通用健康知识，不是你的设备记录；涉及健康决策请以医生意见为准。）';

/// 拆掉来源标记之后的回答。
class ParsedRemoteAnswer {
  const ParsedRemoteAnswer(this.body, {this.isKnowledge = false});

  /// 去掉标记的正文。
  final String body;

  /// 这条回答只用通用知识、没用到记录。
  final bool isKnowledge;
}

/// 按结尾的来源标记拆解在线回答。
///
/// 没有标记时原样返回（[ParsedRemoteAnswer.isKnowledge] 为 false），
/// 界面按「在线」展示——缺标记只是少一层归类，不该让用户拿不到回答。
ParsedRemoteAnswer parseRemoteAnswer(String answer) {
  final match = _sourceMarker.firstMatch(answer);
  if (match == null) return ParsedRemoteAnswer(answer);
  final marker = (match.group(1) ?? '').replaceAll(' ', '');
  return ParsedRemoteAnswer(
    answer.substring(0, match.start).trimRight(),
    isKnowledge: marker == 'AI知识',
  );
}

/// 在线回答的数字回验。
///
/// 在线模型最危险也最容易被忽略的失败不是答得难听，而是**编造一个不存在的次数**
/// ——「本周记录了 12 次」而摘要是 8 次。次数可以精确校验，所以这里做一次
/// 确定性回验。
///
/// 三条设计约束：
/// - **只报告，不回绝、不改写回答**：回验可能误判，静默替换掉回答比原样展示更糟；
/// - **允许集合包含派生数字**：规则引擎算出来的「连续 3 天」「1–5 之间」本来就
///   来自摘要，模型复述它们不算编造，所以直接复用 [evaluateObservations]；
/// - **绝不抛异常**：回验失败必须放行，不能因为校验出问题让用户拿不到回答。

/// 日期与时间串要先摘掉，否则「最后同步于 2026-09-23 08:00」里的数字会被当成
/// 凭空出现的统计结论。小数秒也要吃掉：`DateTime.toString()` 会给出 `.000`。
final RegExp _dateTimePattern =
    RegExp(r'\d{4}-\d{1,2}-\d{1,2}([ T]\d{1,2}:\d{2}(:\d{2})?(\.\d+)?)?');

final RegExp _integerPattern = RegExp(r'\d+');

/// 回答里出现的、摘要无法解释的数字，去重后升序返回。
List<int> numbersNotInSummary(
  String answer,
  AssistantContext context, {
  DateTime? now,
}) {
  final allowed = _allowedNumbers(context, now: now);
  final suspicious = _numbersIn(
    answer,
  ).where((value) => !allowed.contains(value));
  return suspicious.toList()..sort();
}

/// 回验不通过时追加的提醒；没有可疑数字时返回 null。
///
/// 措辞必须是非结论性的：我们不替模型改口，也不重复一遍「以摘要为准」之外的判断。
String? mismatchNotice(List<int> suspicious) {
  if (suspicious.isEmpty) return null;
  return '（提醒：本次回答里的 ${suspicious.join('、')} 与当前统计摘要对不上，'
      '请以概览页的数字为准。）';
}

/// 在线回答的安全网：对不上时追加一句提醒，出任何问题都原样返回回答。
String verifyRemoteAnswer(
  String answer,
  AssistantContext context, {
  DateTime? now,
}) {
  try {
    final notice = mismatchNotice(
      numbersNotInSummary(answer, context, now: now),
    );
    return notice == null ? answer : '$answer\n\n$notice';
  } catch (_) {
    return answer;
  }
}

/// 摘要有依据的全部数字：原始计数 + 逐日序列 + 窗口长度 + 规则观察里的派生数。
Set<int> _allowedNumbers(AssistantContext context, {DateTime? now}) {
  final allowed = <int>{
    context.todayCount,
    context.last7DaysCount,
    context.invalidEventCount,
    context.unknownTimeCount,
    context.futureTimeCount,
    context.totalCount,
    context.dailyCounts.length,
    ...context.dailyCounts,
  };
  for (final observation
      in evaluateObservations(context, now: now ?? DateTime.now())) {
    allowed.addAll(_numbersIn(observation.text));
  }
  return allowed;
}

Set<int> _numbersIn(String text) {
  final numbers = <int>{};
  // 先摘掉日期时间，再看剩下的整数。
  final cleaned = text.replaceAll(_dateTimePattern, ' ');
  for (final match in _integerPattern.allMatches(cleaned)) {
    final value = int.tryParse(match.group(0)!);
    // 超出 int 范围的长数字不可能来自摘要，直接跳过（放行优于误报）。
    if (value != null) numbers.add(value);
  }
  return numbers;
}
