import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'assistant_credentials.dart';
import 'assistant_exception.dart';
import 'providers/gateway_assistant_provider.dart';

/// 一条在线助手配置的**编辑表单**（新增或修改）。
///
/// 它只管收集字段并返回 [AssistantProfile]，不碰安全存储——落盘由
/// `AssistantApiConsole` 统一负责。保存前会用 `toProvider()` 试构造一次，
/// 地址或 Key 不完整就地报错，不让一条用不了的配置存进列表。
///
/// 表单同时承担两件事，缺一不可：
/// 1. **便捷**：常见服务点一下自动填好地址与模型名，不用去翻文档；
/// 2. **透明**：保存前明确列出会发送什么、不发送什么、凭据存在哪。
class AssistantSettingsDialog extends StatefulWidget {
  const AssistantSettingsDialog({super.key, this.initial});

  /// 要修改的配置；为 null 表示新增。
  final AssistantProfile? initial;

  @override
  State<AssistantSettingsDialog> createState() =>
      _AssistantSettingsDialogState();
}

/// 常见 OpenAI 兼容服务，只用于「点一下填好示例」。
///
/// 这不是推荐列表，也不代表我们验证过这些服务：任何 OpenAI 兼容地址都可以手填。
/// 名字只在用户没填时补上。
class _ModelPreset {
  const _ModelPreset(this.label, this.baseUrl, this.model);

  final String label;
  final String baseUrl;
  final String model;
}

const _presets = [
  _ModelPreset('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  _ModelPreset(
    '通义千问',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'qwen-plus',
  ),
  _ModelPreset('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
  _ModelPreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
];

class _AssistantSettingsDialogState extends State<AssistantSettingsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _token;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  late OnlineAssistantMode _mode;
  String? _error;
  bool _consented = false;

  /// 凭据默认打码；「显示」只是让用户确认自己填的是哪一个，不做任何持久化。
  bool _showSecret = false;

  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _mode = initial?.mode ?? OnlineAssistantMode.gateway;
    _name = TextEditingController(text: initial?.name ?? '');
    _endpoint = TextEditingController(
      text: initial?.endpoint ??
          const String.fromEnvironment('ASSISTANT_GATEWAY_URL'),
    );
    _token = TextEditingController(text: initial?.accessToken ?? '');
    _baseUrl = TextEditingController(text: initial?.baseUrl ?? '');
    _apiKey = TextEditingController(text: initial?.apiKey ?? '');
    _model = TextEditingController(text: initial?.model ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _token.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  /// 点一下预设：填地址和模型名，名字空着才补。
  void _applyPreset(_ModelPreset preset) {
    setState(() {
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.model;
      if (_name.text.trim().isEmpty) _name.text = preset.label;
      _error = null;
      _testResult = null;
    });
  }

  void _save() {
    var profile = AssistantProfile(
      id: widget.initial?.id ?? newProfileId(),
      name: _name.text.trim(),
      mode: _mode,
      endpoint: _endpoint.text.trim(),
      accessToken: _token.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
    );
    if (profile.name.isEmpty) profile = profile.withName(profile.autoName());
    try {
      // 试构造一次：地址/Key 不完整当场说清楚，别存下一条用不了的配置。
      profile.toProvider();
    } on AssistantException catch (error) {
      setState(() => _error = error.message);
      return;
    } catch (_) {
      setState(() => _error = '这条配置不完整，请检查各项后重试。');
      return;
    }
    Navigator.of(context).pop(profile);
  }

  /// 只验证「地址通不通」，不发问题、不发摘要，也不带访问码。
  ///
  /// 走的是网关的 `/healthz`，它只返回 status 与 mode，不含任何凭据或数据。
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    String result;
    try {
      final endpoint = GatewayAssistantProvider.validateEndpoint(
        _endpoint.text,
      );
      // 去掉查询参数：healthz 不需要它们，也不该把它们带出去。
      final health = endpoint.replace(path: '/healthz', query: '');
      final request = await client.getUrl(health);
      request.followRedirects = false;
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 2048) {
          throw const FormatException('健康检查响应过大');
        }
        bytes.addAll(chunk);
      }
      if (response.statusCode != HttpStatus.ok) {
        result = '网关返回 ${response.statusCode}，请检查地址。';
      } else {
        final data = jsonDecode(utf8.decode(bytes));
        final mode = data is Map ? data['mode'] : null;
        result = mode is String ? '可连接（网关上游模式：$mode）' : '可连接';
      }
    } on AssistantException catch (error) {
      result = error.message;
    } on TimeoutException {
      result = '连接超时，请检查网络与地址。';
    } on SocketException {
      result = '无法连接，请检查地址与网络。';
    } on HandshakeException {
      result = '证书验证失败，请联系服务管理员。';
    } catch (_) {
      result = '无法确认该地址是否为助手网关。';
    } finally {
      client.close(force: true);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? '添加 API' : '修改 API'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                key: const Key('profile-name'),
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '名字（可选）',
                  hintText: '例如：DeepSeek / 团队网关',
                ),
              ),
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
                  _testResult = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == OnlineAssistantMode.gateway)
                ..._buildGatewayFields(theme)
              else
                ..._buildOwnModelFields(theme),
              const SizedBox(height: 4),
              _buildPrivacyNotice(theme),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consented,
                onChanged: (value) =>
                    setState(() => _consented = value ?? false),
                title: const Text('同意每次提问发送问题和当前记录统计摘要'),
                subtitle: const Text('只发送上面列出的内容；不发送原始记录、设备标识和历史对话。'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
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
          onPressed: _consented ? _save : null,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildSecretField({
    required TextEditingController controller,
    required Key key,
    required String label,
  }) =>
      TextField(
        controller: controller,
        key: key,
        obscureText: !_showSecret,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showSecret = !_showSecret),
            icon: Icon(
              _showSecret
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            tooltip: _showSecret ? '隐藏' : '显示',
          ),
        ),
      );

  List<Widget> _buildGatewayFields(ThemeData theme) => [
        Text(
          '填写团队提供的助手服务地址；摘要由团队网关转发给模型。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endpoint,
          key: const Key('gateway-endpoint'),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '助手服务地址',
            helperText: '示例：https://assistant.example.com/v1/assistant/chat',
            helperMaxLines: 2,
          ),
        ),
        _buildSecretField(
          controller: _token,
          key: const Key('gateway-token'),
          label: '网关访问码（由团队提供）',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('测试连接'),
            ),
            const SizedBox(width: 12),
            if (_testResult != null)
              Expanded(
                child: Text(
                  _testResult!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ];

  List<Widget> _buildOwnModelFields(ThemeData theme) => [
        Text(
          '填写你自己的模型服务。API Key 只在这台手机上使用，不发给团队服务器，也不写入日志。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text('常见服务（点一下自动填地址和模型名）', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final preset in _presets)
              ActionChip(
                label: Text(preset.label),
                onPressed: () => _applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseUrl,
          key: const Key('model-base-url'),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '模型服务地址',
            helperText: '填到 /v1 即可，App 会自动补 /chat/completions',
            hintText: 'https://api.deepseek.com/v1',
            helperMaxLines: 2,
          ),
        ),
        _buildSecretField(
          controller: _apiKey,
          key: const Key('model-api-key'),
          label: '你的 API Key',
        ),
        TextField(
          controller: _model,
          key: const Key('model-name'),
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '模型名称',
            helperText: '要和服务商的文档一致',
            hintText: 'deepseek-chat',
            helperMaxLines: 2,
          ),
        ),
      ];

  /// 保存前必须看到的说明：发什么、不发什么、凭据在哪。
  ///
  /// 直连模式与网关模式的第三条不同——这正是用户最容易搞混的地方，
  /// 所以按模式切换文案，而不是写一句含糊的通用说明。
  Widget _buildPrivacyNotice(ThemeData theme) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('每次提问会发送什么', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              '· 你本次输入的问题原文（其中可能包含你自己填写的个人信息）\n'
              '· 记录统计摘要：今日与近 7 天次数、逐日次数、疑似无效条数、'
              '时间未知与未来时间条数、最后同步时间、是否为演示数据',
            ),
            const SizedBox(height: 10),
            Text('不会发送什么', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text('· 原始记录与单条时间戳 · 设备标识或蓝牙地址 · 历史对话 · 任何密钥'),
            const SizedBox(height: 10),
            Text('凭据保存在哪', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              _mode == OnlineAssistantMode.gateway
                  ? '· 按「保存」即写入本机安全存储（Android Keystore / iOS Keychain），'
                      '可在「管理 API」里随时删除。\n'
                      '· 摘要经团队网关转发给模型；模型密钥只在服务器上，App 拿不到。'
                  : '· 按「保存」即写入本机安全存储（Android Keystore / iOS Keychain），'
                      '可在「管理 API」里随时删除。\n'
                      '· Key 由本机直接发给上面填写的模型服务，不经过团队服务器，也不写入日志。',
            ),
          ],
        ),
      );
}
