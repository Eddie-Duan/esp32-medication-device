import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'assistant_api_console.dart';
import 'assistant_credentials.dart';
import 'assistant_service.dart';
import 'assistant_exception.dart';
import 'models/assistant_context.dart';
import 'models/chat_message.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    this.service,
    this.assistantContext = const AssistantContext(),
    this.contextLoader,
    this.store,
  });

  final AssistantService? service;
  final AssistantContext assistantContext;
  final Future<AssistantContext> Function()? contextLoader;

  /// 已保存的在线 API。测试注入用；默认走系统安全存储。
  final AssistantCredentialsStore? store;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late AssistantService _service;
  late final AssistantCredentialsStore _store;
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
    _context = widget.assistantContext;
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _messages = [
      ChatMessage(
        role: ChatRole.assistant,
        text:
            '你好，我可以解释${_context.isDemo ? '演示数据' : '本地设备记录'}的统计。${_service.isRemote ? '当前使用在线助手。' : '当前使用本地规则回答，不联网。'}记录的动作次数不代表确认服药。',
        createdAt: DateTime.now(),
      ),
    ];
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

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
    _scrollToBottom();

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
          ),
        );
      });
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
      setState(() {
        _service = AssistantService();
        _resetConversation('已切回本地摘要，不联网。');
      });
      return;
    }
    // 已经配置过就直接用选中的那条，不再弹窗——用户要的是「点一下就切」。
    final provider = await buildSelectedProvider(_store);
    if (!mounted) return;
    if (provider == null) {
      await _openConsole();
      return;
    }
    setState(() {
      _service = AssistantService(provider: provider, isRemote: true);
      _resetConversation(_onlineNotice);
    });
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
    setState(() {
      _service = service;
      _resetConversation(_onlineNotice);
    });
  }

  /// 换了上游之后，旧回答的来源已经对不上当前模式，所以清空并要求重新提问。
  void _resetConversation(String notice) {
    _messages
      ..clear()
      ..add(
        ChatMessage(
          role: ChatRole.assistant,
          text: notice,
          createdAt: DateTime.now(),
        ),
      );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('用药记录助手'),
        actions: [
          IconButton(
            onPressed: _sending ? null : _openConsole,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '管理 API',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          _buildModeBar(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) => index == _messages.length
                  ? _buildThinkingBubble()
                  : _buildMessage(_messages[index]),
            ),
          ),
          _buildQuickQuestions(),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// 常驻的模式切换条。
  ///
  /// 之前切换藏在右上角菜单里，用户找不到、也看不出当前在用什么；现在直接显示
  /// 本地/在线两段，选中态就是当前上游。
  Widget _buildModeBar() {
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
              selected: {_service.isRemote},
              onSelectionChanged: _sending
                  ? null
                  : (selection) => _changeMode(selection.single),
            ),
          ),
          if (_service.isRemote) ...[
            const SizedBox(height: 8),
            _buildPrivacyBanner(),
          ],
        ],
      ),
    );
  }

  /// 在线时把「按下发送会发生什么」放在输入框上方，而不是只写在设置页里。
  Widget _buildPrivacyBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem(
                  data.isDemo ? '今日 · 演示' : '今日',
                  '${data.todayCount} 次',
                ),
                _summaryItem('近 7 天', '${data.last7DaysCount} 次'),
                _summaryItem('近 7 天疑似无效', '${data.invalidEventCount} 条'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '近 7 天逐日使用动作（左最早，右今天）',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
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
                            data.dailyCounts[index] / max * 28,
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
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final colorScheme = Theme.of(context).colorScheme;
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
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(message.text),
        ),
      ),
    );
  }

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

  Widget _buildQuickQuestions() {
    return SizedBox(
      height: 42,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _quickQuestion('今天用了几次？'),
          _quickQuestion('最近有异常吗？'),
          _quickQuestion('查看最近一周'),
          _quickQuestion('有什么建议？'),
        ],
      ),
    );
  }

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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '输入关于记录的问题',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
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
      ),
    );
  }
}
