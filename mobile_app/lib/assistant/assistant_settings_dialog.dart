import 'package:flutter/material.dart';

import 'assistant_exception.dart';
import 'assistant_provider.dart';
import 'assistant_service.dart';
import 'providers/direct_llm_assistant_provider.dart';
import 'providers/gateway_assistant_provider.dart';

/// 在线助手的两种上游。凭据只保存在当前页面内存里，退出即失效。
enum OnlineAssistantMode { gateway, ownModel }

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
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  OnlineAssistantMode _mode = OnlineAssistantMode.gateway;
  String? _error;
  bool _consented = false;

  @override
  void dispose() {
    _endpoint.dispose();
    _token.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _connect() {
    try {
      final AssistantProvider provider = switch (_mode) {
        OnlineAssistantMode.gateway => GatewayAssistantProvider(
            endpoint: _endpoint.text,
            accessToken: _token.text.trim(),
          ),
        OnlineAssistantMode.ownModel => DirectLlmAssistantProvider(
            baseUrl: _baseUrl.text,
            apiKey: _apiKey.text.trim(),
            model: _model.text.trim(),
          ),
      };
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
            const Text('在线助手会把本次问题和统计摘要发给模型。凭据只保存在本次页面内存，退出后失效。'),
            const SizedBox(height: 12),
            SegmentedButton<OnlineAssistantMode>(
              segments: const [
                ButtonSegment(
                  value: OnlineAssistantMode.gateway,
                  label: Text('团队网关'),
                  icon: Icon(Icons.cloud_outlined),
                ),
                ButtonSegment(
                  value: OnlineAssistantMode.ownModel,
                  label: Text('我自己的模型'),
                  icon: Icon(Icons.key_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => setState(() {
                _mode = selection.single;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_mode == OnlineAssistantMode.gateway) ...[
              const Text('填写团队提供的助手服务地址；摘要由团队网关转发给模型。'),
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
            ] else ...[
              const Text('填写你自己的模型服务。API Key 只在这台手机上使用，不发给团队服务器，也不写入日志。'),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                key: const Key('model-base-url'),
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '模型服务地址',
                  hintText: 'https://api.deepseek.com/v1',
                ),
              ),
              TextField(
                controller: _apiKey,
                key: const Key('model-api-key'),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '你的 API Key'),
              ),
              TextField(
                controller: _model,
                key: const Key('model-name'),
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: 'deepseek-chat',
                ),
              ),
            ],
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
