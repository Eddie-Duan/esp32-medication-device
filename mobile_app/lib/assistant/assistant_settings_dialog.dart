import 'package:flutter/material.dart';

import 'assistant_exception.dart';
import 'assistant_service.dart';
import 'providers/gateway_assistant_provider.dart';

/// Runtime credentials stay in memory for this assistant page only.
class AssistantSettingsDialog extends StatefulWidget {
  const AssistantSettingsDialog({super.key});

  @override
  State<AssistantSettingsDialog> createState() =>
      _AssistantSettingsDialogState();
}

class _AssistantSettingsDialogState extends State<AssistantSettingsDialog> {
  final _endpoint = TextEditingController(
    text: const String.fromEnvironment('ASSISTANT_GATEWAY_URL'),
  );
  final _token = TextEditingController();
  String? _error;
  bool _consented = false;

  @override
  void dispose() {
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  void _connect() {
    try {
      final provider = GatewayAssistantProvider(
        endpoint: _endpoint.text,
        accessToken: _token.text.trim(),
      );
      Navigator.of(
        context,
      ).pop(AssistantService(provider: provider, isRemote: true));
    } on AssistantException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('在线助手设置'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填写团队提供的助手服务地址。设置在退出此页面后失效。'),
            const SizedBox(height: 12),
            TextField(
              controller: _endpoint,
              key: const Key('gateway-endpoint'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '助手服务地址'),
            ),
            TextField(
              controller: _token,
              key: const Key('gateway-token'),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '网关访问码（由团队提供）'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consented,
              onChanged: (value) => setState(() => _consented = value ?? false),
              title: const Text('同意每次提问发送问题和当前记录统计摘要'),
              subtitle: const Text('包含次数、异常计数、最后同步时间及演示标记；不发送原始记录、设备标识和历史对话。'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _consented ? _connect : null,
        child: const Text('启用在线助手'),
      ),
    ],
  );
}
