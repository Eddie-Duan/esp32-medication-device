import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'assistant_api_console.dart';
import 'assistant_chat_store.dart';
import 'assistant_credentials.dart';
import 'assistant_service.dart';
import 'assistant_exception.dart';
import 'models/assistant_context.dart';
import 'models/chat_message.dart';

/// 本地与在线两种上游的识别色。全页的强调色只有这两枚，换配色只改这里。
///
/// 在线用靛蓝而不是另一档青绿：这两个颜色在一屏里会同时出现（分段控件、
/// 来源小标、发送按钮），色相差距太小就等于没区分。
const _localAccent = Color(0xff147d79);
const _onlineAccent = Color(0xff4f6bd9);

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    this.service,
    this.assistantContext = const AssistantContext(),
    this.contextLoader,
    this.store,
    this.chatStore,
    this.themeController,
  });

  final AssistantService? service;
  final AssistantContext assistantContext;
  final Future<AssistantContext> Function()? contextLoader;

  /// 已保存的在线 API。测试注入用；默认走系统安全存储。
  final AssistantCredentialsStore? store;

  /// 聊天记录存储。测试注入内存实现；默认写本机偏好存储。
  final AssistantChatStore? chatStore;

  /// 外观设置。为空时不显示「外观」菜单项（点了没反应比不显示更糟）。
  final AppThemeController? themeController;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late AssistantService _service;
  late final AssistantCredentialsStore _store;
  late final AssistantChatStore _chatStore;
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final List<ChatMessage> _messages;
  bool _sending = false;
  late AssistantContext _context;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AssistantService();
    _store = widget.store ?? SecureAssistantCredentialsStore();
    _chatStore = widget.chatStore ?? SharedPreferencesAssistantChatStore();
    _context = widget.assistantContext;
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _messages = [_welcomeMessage()];
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 开场白是 App 自己写的，不带来源标（它不是哪个上游的回答）。
  ChatMessage _welcomeMessage() => ChatMessage(
    role: ChatRole.assistant,
    text:
        '你好，我可以解释${_context.isDemo ? '演示数据' : '本地设备记录'}的统计。'
        '${_service.isRemote ? '当前使用在线助手。' : '当前使用本地规则回答，不联网。'}'
        '记录的动作次数不代表确认服药。',
    createdAt: DateTime.now(),
  );

  /// 读本机历史。读不到、或本来就空，就保留开场白。
  Future<void> _loadHistory() async {
    final history = await _chatStore.load();
    if (!mounted || history.isEmpty) return;
    // 读盘期间用户可能已经提问了，那种情况下不能把刚发的消息覆盖掉。
    if (_messages.length > 1) return;
    setState(() => _messages
      ..clear()
      ..addAll(history));
    _scrollToBottom();
  }

  /// 每次消息变动后落盘。
  ///
  /// 故意不 await：写失败也只是这次没存上（见 [AssistantChatStore] 的失败语义），
  /// 不该让发送流程等磁盘。
  void _persistHistory() => unawaited(_chatStore.save(List.of(_messages)));

  Future<void> _send([String? preset]) async {
    final question = (preset ?? _inputController.text).trim();
    if (question.isEmpty || _sending) return;

    _inputController.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          role: ChatRole.user,
          text: question,
          createdAt: DateTime.now(),
        ),
      );
      _sending = true;
    });
    _persistHistory();
    _scrollToBottom();

    // 回答是提问那一刻的上游给出的：等待期间用户可能切了模式，
    // 失败气泡的来源要按切换前算，否则会标错。
    final wasRemote = _service.isRemote;

    try {
      final latestContext =
          await widget.contextLoader?.call() ?? widget.assistantContext;
      if (!mounted) return;
      setState(() => _context = latestContext);
      final answer = await _service.ask(
        question: question,
        context: latestContext,
      );
      if (!mounted) return;
      setState(() => _messages.add(answer));
      _persistHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            text: error is AssistantException
                ? error.message
                : '暂时无法读取记录或获取回答，请稍后重试。',
            createdAt: DateTime.now(),
            source: wasRemote ? ChatSource.online : ChatSource.local,
          ),
        );
      });
      _persistHistory();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  /// 切换上游。回本地是一步；切在线时如果已经配置过 API 也是一步。
  Future<void> _changeMode(bool remote) async {
    if (_sending || remote == _service.isRemote) return;
    if (!remote) {
      setState(() => _service = AssistantService());
      _appendNotice('已切回本地摘要，不联网。');
      return;
    }
    // 已经配置过就直接用选中的那条，不再弹窗——用户要的是「点一下就切」。
    final provider = await buildSelectedProvider(_store);
    if (!mounted) return;
    if (provider == null) {
      await _openConsole();
      return;
    }
    setState(() => _service = AssistantService(provider: provider, isRemote: true));
    _appendNotice(_onlineNotice);
  }

  static const _onlineNotice =
      '已启用在线助手。每次提问只发送本次问题和当前统计摘要；历史对话不上传。';

  Future<void> _openConsole() async {
    if (_sending) return;
    final service = await showDialog<AssistantService>(
      context: context,
      builder: (_) => AssistantApiConsole(store: _store),
    );
    if (service == null || !mounted) return;
    setState(() => _service = service);
    _appendNotice(_onlineNotice);
  }

  /// 切换上游时插入一条分隔提示，**不再清空对话**。
  ///
  /// 清空看起来只是「干净」，实际是把用户的东西删了：刚在本地问到的答案、
  /// 在线追问的上下文，切一下模式就全没了。历史里每条回答都带来源标，
  /// 本地答和在线答混着看也不会认错，所以没有清空的必要。
  void _appendNotice(String notice) {
    setState(
      () => _messages.add(
        ChatMessage(
          role: ChatRole.system,
          text: notice,
          createdAt: DateTime.now(),
        ),
      ),
    );
    _persistHistory();
    _scrollToBottom();
  }

  /// 清空本机聊天记录。
  ///
  /// 聊天已经落盘，就必须给删除入口：内容里有记录摘要和在线回答，
  /// 用户要能一键抹掉，而不是只能去系统设置里清应用数据。
  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空对话？'),
        content: const Text('会删除本机保存的聊天记录。用药记录本身不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _chatStore.clear();
    if (!mounted) return;
    setState(() => _messages
      ..clear()
      ..add(_welcomeMessage()));
    _persistHistory();
  }

  List<PopupMenuEntry<String>> _menuItems(ThemeMode? mode) => [
    const PopupMenuItem(value: 'clear', child: Text('清空对话')),
    if (mode != null) ...[
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        value: 'system',
        checked: mode == ThemeMode.system,
        child: const Text('外观：跟随系统'),
      ),
      CheckedPopupMenuItem(
        value: 'light',
        checked: mode == ThemeMode.light,
        child: const Text('外观：浅色'),
      ),
      CheckedPopupMenuItem(
        value: 'dark',
        checked: mode == ThemeMode.dark,
        child: const Text('外观：深色'),
      ),
    ],
  ];

  Widget _buildOverflowMenu() {
    final theme = widget.themeController;
    if (theme == null) {
      return PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: _onMenuSelected,
        itemBuilder: (_) => _menuItems(null),
      );
    }
    // 勾选状态要跟着当前模式走，所以菜单本身也要监听。
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: theme.mode,
      builder: (context, mode, _) => PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: _onMenuSelected,
        itemBuilder: (_) => _menuItems(mode),
      ),
    );
  }

  Future<void> _onMenuSelected(String value) async {
    if (value == 'clear') {
      await _clearConversation();
      return;
    }
    final theme = widget.themeController;
    if (theme != null) await theme.setMode(parseThemeMode(value));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = _service.isRemote ? _onlineAccent : _localAccent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('用药记录助手'),
        actions: [
          IconButton(
            onPressed: _sending ? null : _openConsole,
            icon: Icon(Icons.settings_outlined, color: accent),
            tooltip: '管理 API',
          ),
          _buildOverflowMenu(),
        ],
      ),
      // 键盘弹起时可用高度会变小。真正占高的摘要卡放进可滚动区随内容滚走，
      // 输入栏固定在底部——这样就不会再出现「输入框被挤出屏幕、看不到打的字」的
      // RenderFlex 溢出（原来摘要卡是固定项，键盘一来就把输入栏顶出屏幕）。
      body: SafeArea(
        child: Column(
          children: [
            _buildModeBar(),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  _buildSummaryCard(),
                  for (final message in _messages) _buildMessage(message),
                  if (_sending) _buildThinkingBubble(),
                ],
              ),
            ),
            // 快捷问题留在固定区：它是「随时点一下」的入口，滚走了就不好用。
            _buildQuickQuestions(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// 常驻的模式切换条。
  ///
  /// 之前切换藏在右上角菜单里，用户找不到、也看不出当前在用什么；现在直接显示
  /// 本地/在线两段，选中态就是当前上游。
  Widget _buildModeBar() {
    final remote = _service.isRemote;
    final accent = remote ? _onlineAccent : _localAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('本地'),
                  icon: Icon(Icons.offline_bolt_outlined, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('在线'),
                  icon: Icon(Icons.cloud_outlined, size: 16),
                ),
              ],
              selected: {remote},
              // 选中段直接上识别色，一眼看出现在问的是谁。选中态是
              // WidgetState.selected，只能靠 resolveWith 表达（不能整段染色，
              // 否则未选中的那段也跟着变色，就看不出选的是哪个了）。
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.selected) ? accent : null,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white
                      : null,
                ),
              ),
              onSelectionChanged: _sending
                  ? null
                  : (selection) => _changeMode(selection.single),
            ),
          ),
          if (remote) ...[
            const SizedBox(height: 8),
            _buildPrivacyBanner(),
          ],
        ],
      ),
    );
  }

  /// 在线时把「按下发送会发生什么」放在输入框上方，而不是只写在设置页里。
  Widget _buildPrivacyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _assistantBubbleColor(context, ChatSource.online),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 16,
            color: _sourceAccent(context, ChatSource.online),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '每次提问只把「本次问题 + 上方摘要」发给在线模型，'
              '不发送原始记录、设备标识或历史对话。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final data = _context;
    return Card(
      // 横向留白由外层 ListView 给，卡片自己只管上下间距。
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 三列都得能被压窄。Row 里没有弹性项时，每一项都按文字固有宽度占位，
                // 系统字号放大后「近 7 天疑似无效」这种长标签就会把整行顶出卡片
                // （实测 1.5 倍字号、375 宽时横向溢出 12 像素）。
                Flexible(
                  child: _summaryItem(
                    data.isDemo ? '今日 · 演示' : '今日',
                    '${data.todayCount} 次',
                  ),
                ),
                Flexible(
                  child: _summaryItem('近 7 天', '${data.last7DaysCount} 次'),
                ),
                Flexible(
                  child: _summaryItem(
                    '近 7 天疑似无效',
                    '${data.invalidEventCount} 条',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _buildDailyBars(data),
          ],
        ),
      ),
    );
  }

  /// 把助手实际读到的逐日数据画出来，让用户看得见助手“知道什么”，
  /// 而不是只面对三个汇总数字。
  Widget _buildDailyBars(AssistantContext data) {
    final max = data.dailyCounts.fold<int>(
      1,
      (current, count) => math.max(current, count),
    );
    // 柱子上的数字会随系统字号放大，柱区高度也跟着放大，否则大字体会把它撑爆
    // （同一类溢出：固定高度装不下会被 textScaler 放大的文字）。
    final scale = MediaQuery.textScalerOf(context).scale(1);
    const barAreaHeight = 52.0;
    const maxBarHeight = 28.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '近 7 天逐日使用动作（左最早，右今天）',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: barAreaHeight * scale,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < data.dailyCounts.length; index++)
                Expanded(
                  child: Semantics(
                    label:
                        '第 ${index + 1} 天，${data.dailyCounts[index]} 次使用动作',
                    excludeSemantics: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${data.dailyCounts[index]}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 14,
                          height: math.max(
                            3,
                            data.dailyCounts[index] / max * maxBarHeight * scale,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '共 ${data.totalCount} 条本地记录'
          '${data.lastSyncAt == null ? '' : ' · 最后同步 ${data.lastSyncAt!.toLocal()}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _summaryItem(String title, String value) {
    return Column(
      children: [
        // 被压窄后标题会折行，居中才不像排版事故。
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 助手气泡的底色。
  ///
  /// 深色模式不能沿用浅色模式的淡底：淡底配深色模式下的浅色文字会读不出来，
  /// 所以两套都写出来，只按当前亮度取值。
  Color _assistantBubbleColor(BuildContext context, ChatSource? source) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (source) {
      ChatSource.knowledge =>
        dark ? const Color(0xff3a3320) : const Color(0xfffdf3dc),
      ChatSource.online =>
        dark ? const Color(0xff26304d) : const Color(0xffe6eafb),
      _ => dark ? const Color(0xff1d3836) : const Color(0xffe0efed),
    };
  }

  /// 来源小标的颜色。深色模式下用亮一档的同色相，否则贴在深底上看不清。
  Color _sourceAccent(BuildContext context, ChatSource source) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (source) {
      ChatSource.knowledge =>
        dark ? const Color(0xffe6c879) : const Color(0xff8a6d1f),
      ChatSource.online =>
        dark ? const Color(0xff9fb2ff) : _onlineAccent,
      ChatSource.local => dark ? const Color(0xff7fd0c8) : _localAccent,
    };
  }

  /// 来源小标的图标与文字。
  ///
  /// 措辞用「本地回答 / 在线回答 / AI 知识」，与分段控件的「本地 / 在线」不同字，
  /// 这样界面上的两处标签不会互相混淆（测试里也靠这一点区分）。
  ({String label, IconData icon}) _sourceBadge(ChatSource source) =>
      switch (source) {
        ChatSource.local => (
          label: '本地回答',
          icon: Icons.offline_bolt_outlined,
        ),
        ChatSource.online => (label: '在线回答', icon: Icons.cloud_outlined),
        ChatSource.knowledge => (
          label: 'AI 知识',
          icon: Icons.lightbulb_outline,
        ),
      };

  Widget _buildMessage(ChatMessage message) {
    if (message.isNotice) return _buildNotice(message);
    final colorScheme = Theme.of(context).colorScheme;
    final source = message.source;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        // 读屏时需要听出这是谁说的话，否则提问和回答会混在一起。
        label: '${message.isUser ? '我的提问' : '助手回答'}：${message.text}',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: message.isUser
                ? colorScheme.primaryContainer
                : _assistantBubbleColor(context, source),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用户提问不带来源标：问句本身没有来源差异。
              if (!message.isUser && source != null) ...[
                _buildSourceBadge(source),
                const SizedBox(height: 4),
              ],
              Text(message.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(ChatSource source) {
    final badge = _sourceBadge(source);
    final accent = _sourceAccent(context, source);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(badge.icon, size: 12, color: accent),
        const SizedBox(width: 4),
        Text(
          badge.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: accent,
          ),
        ),
      ],
    );
  }

  /// 切换上游的分隔提示：居中的淡色小字，不是气泡——它不是谁说的话。
  Widget _buildNotice(ChatMessage message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          message.text,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  /// 在线助手最长可能等 55 秒；只靠发送按钮上的小转圈，对话区看起来像卡死了。
  Widget _buildThinkingBubble() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(_service.isRemote ? '正在询问在线助手…' : '正在读取本地统计…'),
        ],
      ),
    ),
  );

  /// 快捷问题。每个都能在本地模式下拿到确定答案，不靠在线模型。
  static const _quickQuestions = [
    '今天用了几次？',
    '最近有异常吗？',
    '查看最近一周',
    '有什么建议？',
    '数据是最新的吗？',
    '设备时间对吗？',
    '一共有多少条记录？',
    '空白那几天怎么看？',
  ];

  Widget _buildQuickQuestions() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // 不给固定高度：系统字号放大时，固定高度会把 chip 里的文字挤爆。
    child: Row(
      children: [for (final question in _quickQuestions) _quickQuestion(question)],
    ),
  );

  Widget _quickQuestion(String question) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        label: Text(question),
        onPressed: _sending ? null : () => _send(question),
      ),
    );
  }

  Widget _buildInputBar() {
    final remote = _service.isRemote;
    final accent = remote ? _onlineAccent : _localAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                // 在线模式可以问记录以外的问题，提示语跟着说清楚；本地模式答不了，
                // 就不要许这个愿。
                hintText: remote ? '问记录，也可以问健康常识' : '输入关于记录的问题',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            tooltip: '发送',
          ),
        ],
      ),
    );
  }
}
