/// 助手可检索的设备知识库（RAG 的检索端），**运行时语料的唯一来源**。
///
/// 语料就是这里。早期另有 `server/assistant-gateway/knowledge/` 下的一份 markdown 副本，
/// 两份靠人肉同步、已经漂移过，所以取消了副本：那个目录现在只写「写什么、怎么写、
/// 怎么验」（收录原则、安全边界、术语、验收），要改助手实际检索到的知识就改本文件。
///
/// 错误码（`STORAGE_UNAVAILABLE` / `READ_FAILED` / `BAD_FILE` / `TOO_MANY_FILES` /
/// `ACK_TIMEOUT`）来自 ESP32 固件同步流程返回的状态码（`flash.ino` 的 `syncError`）。
/// **固件升级后必须复核这些片段**，别让语料停在旧固件的行为上。
///
/// 收录原则（安全边界，改动前先读 `knowledge/README.md`）：
/// - 只放「这个设备和这个 App 自己才知道、通用模型答不了」的权威事实：
///   设备边界、错误码、时间与同步、维护、隐私、术语；
/// - **不放** 药品说明书、剂量表、用药指导、疾病说明 —— 那些会诱导医疗建议，
///   也是最危险的一类。通用健康问答由模型自己的知识 + 来源标记处理，不走这里。
///
/// 检索是关键词子串匹配，不引入 embedding / 向量模型：这个语料只有十几篇，
/// 关键词匹配已经够用，且能保持「全离线、零新依赖、文本不出手机」。
class KnowledgeChunk {
  const KnowledgeChunk({
    required this.id,
    required this.title,
    required this.body,
    required this.keywords,
  });

  /// 稳定 id，测试和日志用它指代某一篇，不要随意改。
  final String id;

  /// 一句话标题，尽量写成用户会问的问题。
  final String title;

  /// 自包含的一段权威解释，检索命中后整段作为「参考资料」喂给模型。
  final String body;

  /// 命中词：问题里出现任一词就倾向于命中这一篇。
  final List<String> keywords;

  /// 拼成给模型看的「参考资料」一行。
  String toReference() => '$title：$body';
}

/// 全量语料。顺序无关，检索按得分排序。
const List<KnowledgeChunk> assistantKnowledge = [
  KnowledgeChunk(
    id: 'boundary.dose',
    title: '设备能测出我吃了多少药吗',
    body: '设备只记录用药动作次数，不测量剂量，也不能确认药是否真的被服用。'
        '它不能告诉你吃了多少药。',
    keywords: ['测出', '吃多少', '多少药', '剂量', '药量'],
  ),
  KnowledgeChunk(
    id: 'boundary.adherence',
    title: '记录能证明我吃药了吗',
    body: '动作次数只代表装置被使用过，不证明实际服药；没有记录也不等于漏服。'
        '设备数据只有近 7 天逐日统计，更早的规律无法判断。',
    keywords: ['服药', '吃药', '规律', '证明', '上个月'],
  ),
  KnowledgeChunk(
    id: 'sync.storage_unavailable',
    title: '同步提示 STORAGE_UNAVAILABLE',
    body: '设备文件系统不可用（尚未初始化或挂载失败）。已经保存的记录不会因此被删除。'
        '由硬件组确认板上无须保留数据后初始化文件系统，'
        '不要在 App 里尝试修复或格式化设备。',
    keywords: ['STORAGE_UNAVAILABLE', '存储不可用', '文件系统'],
  ),
  KnowledgeChunk(
    id: 'sync.read_failed',
    title: '同步提示 READ_FAILED',
    body: '读取某条记录的文件失败。该文件被保留，不会被当作已同步删除。'
        '重新同步通常可以重试；若持续失败，交给硬件组检查存储。',
    keywords: ['READ_FAILED', '读取失败'],
  ),
  KnowledgeChunk(
    id: 'sync.bad_file',
    title: '同步提示 BAD_FILE',
    body: '某个文件的大小或内容不符合记录格式（例如文件被截断，'
        '或时间字段不是有效时间戳）。该文件被跳过并保留。',
    keywords: ['BAD_FILE'],
  ),
  KnowledgeChunk(
    id: 'sync.too_many_files',
    title: '同步提示 TOO_MANY_FILES',
    body: '设备上的记录文件数量超过上限（当前固件 256 个）。'
        '需要先完成同步并提交回收，再继续记录。',
    keywords: ['TOO_MANY_FILES', '文件太多', '文件数量'],
  ),
  KnowledgeChunk(
    id: 'sync.ack_timeout',
    title: '同步提示 ACK_TIMEOUT',
    body: '设备在等待手机确认（ACK）时超时。记录不会被删除，重新同步可以继续。',
    keywords: ['ACK_TIMEOUT'],
  ),
  KnowledgeChunk(
    id: 'time.unknown',
    title: '为什么有条记录显示时间未知',
    body: '记录的时间戳为 0 时视为时间未知，常见原因是设备尚未通过校时。'
        '这类记录不计入按日统计。',
    keywords: ['时间未知', '未知时间', '没时间'],
  ),
  KnowledgeChunk(
    id: 'time.future',
    title: '为什么有条记录的时间是未来',
    body: '记录时间晚于手机当前时间时，会先被排除在按日统计之外。'
        '通常是设备时间不准，建议核对设备的时间设置。',
    keywords: ['未来时间', '时间不对', '时间错', '校时'],
  ),
  KnowledgeChunk(
    id: 'privacy.upload',
    title: '在线提问会发送什么',
    body: '在线只发送本次问题与当前统计摘要（几个计数和近 7 天逐日次数），'
        '不上传原始记录、设备标识或历史对话。',
    keywords: ['上传', '隐私', '发送什么', '联网', '发送'],
  ),
  KnowledgeChunk(
    id: 'maintain.bluetooth',
    title: '蓝牙连不上装置',
    body: '检查设备电量与充电、确认同步按键位置、必要时重新扫描广播窗口；'
        '要在 App 里主动扫描，而不是系统蓝牙配对。',
    keywords: ['蓝牙', '连不上', '连接不上'],
  ),
  KnowledgeChunk(
    id: 'term.daily',
    title: '近 7 天逐日次数怎么算',
    body: '近 7 天逐日次数只统计使用动作，未知与未来时间不计入。'
        '总和等于近 7 天总数。',
    keywords: ['逐日', '每天', '口径', '近 7 天', '近7天'],
  ),
  KnowledgeChunk(
    id: 'time.last_sync',
    title: '最后一次同步时间是什么意思',
    body: '最后一次同步时间只反映本机数据的新旧，不影响记录本身。'
        '距上次同步超过 3 天时，统计可能不含最新记录。',
    keywords: ['同步时间', '最后同步', 'last_sync'],
  ),
];

/// 按关键词做轻量检索，返回按相关度降序的前 [topK] 篇。
///
/// 中文没有天然分词，这里用「关键词是否出现在问题里」做子串匹配：
/// 命中一个关键词得 3 分、命中标题再得 2 分，取总分最高的前几篇。
/// 问题为空或一篇都没命中时返回空列表。
List<KnowledgeChunk> retrieveKnowledge(String question, {int topK = 3}) {
  final q = question.trim();
  if (q.isEmpty) return const [];
  final scored = <({int score, KnowledgeChunk chunk})>[];
  for (final chunk in assistantKnowledge) {
    var score = 0;
    for (final keyword in chunk.keywords) {
      if (q.contains(keyword)) score += 3;
    }
    if (q.contains(chunk.title)) score += 2;
    if (score > 0) scored.add((score: score, chunk: chunk));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return [for (final entry in scored.take(topK)) entry.chunk];
}
