import 'package:flutter/material.dart';

import 'assistant_service.dart';
import 'models/assistant_context.dart';
import 'models/chat_message.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    this.service,
    this.assistantContext = const AssistantContext(),
    this.contextLoader,
  });

  final AssistantService? service;
  final AssistantContext assistantContext;
  final Future<AssistantContext> Function()? contextLoader;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late final AssistantService _service;
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final List<ChatMessage> _messages;
  bool _sending = false;
  late AssistantContext _context;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AssistantService();
    _context = widget.assistantContext;
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _messages = [
      ChatMessage(
        role: ChatRole.assistant,
        text:
            '你好，我可以解释${_context.isDemo ? '演示数据' : '本地设备记录'}的统计。当前使用本地规则回答，不联网。记录的动作次数不代表确认服药。',
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
      _messages.add(ChatMessage(
        role: ChatRole.user,
        text: question,
        createdAt: DateTime.now(),
      ));
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
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '助手暂时不可用：$error',
          createdAt: DateTime.now(),
        ));
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
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
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text('Mock'),
                avatar: Icon(Icons.science_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessage(_messages[index]),
            ),
          ),
          _buildQuickQuestions(),
          _buildInputBar(),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _summaryItem(
                data.isDemo ? '今日 · 演示' : '今日', '${data.todayCount} 次'),
            _summaryItem('近 7 天', '${data.last7DaysCount} 次'),
            _summaryItem('近 7 天疑似无效', '${data.invalidEventCount} 条'),
          ],
        ),
      ),
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
    );
  }

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
