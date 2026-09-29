import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'assistant_exception.dart';
import 'assistant_prompt.dart';
import 'assistant_provider.dart';
import 'models/assistant_context.dart';

/// 用**用户自己**的 API Key 直连 OpenAI 兼容接口。
///
/// 与 `GatewayAssistantProvider` 的区别：这里没有团队服务器参与，Key 只存在于
/// 本机内存中，随请求直接发给用户填写的模型服务。因此要区分两类 Key：
///
/// - **团队的/共享的 Key**：绝对不允许写进 App、APK、构建参数或仓库；
/// - **用户自己的 Key**：允许在运行时输入，但只保留在当前页面内存里，
///   不落盘、不进日志、不上传给团队服务器。
///
/// 边界与风险见 `docs/assistant-model-access.md`。
class DirectLlmAssistantProvider implements AssistantProvider {
  DirectLlmAssistantProvider({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 55),
    bool allowLocalHttp = kDebugMode,
  }) : endpoint = validateBaseUrl(baseUrl, allowLocalHttp: allowLocalHttp) {
    // 在构造时报错，设置对话框才能立即提示，而不是等用户按下发送。
    if (apiKey.trim().isEmpty) {
      throw const AssistantException('请先填写模型服务的 API Key。');
    }
    if (model.trim().isEmpty) {
      throw const AssistantException('请先填写模型名称，例如 deepseek-chat。');
    }
  }

  /// 已补上 `/chat/completions` 的完整地址。
  final Uri endpoint;
  final String apiKey;
  final String model;
  final Duration timeout;

  static const maxQuestionLength = 1000;
  static const maxResponseBytes = 64 * 1024;
  static const _chatPath = '/chat/completions';

  /// 只接受 HTTPS（调试版额外允许本机 HTTP），并补齐 `/chat/completions`。
  static Uri validateBaseUrl(String value, {bool allowLocalHttp = kDebugMode}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AssistantException(
          '请输入完整的模型服务地址，例如 https://api.deepseek.com/v1。');
    }
    final localHttp = allowLocalHttp &&
        uri.scheme == 'http' &&
        const ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host);
    if (uri.scheme != 'https' && !localHttp) {
      throw const AssistantException('模型服务地址需要 HTTPS；调试版仅允许本机 HTTP。');
    }
    // 用户可能已经填了完整路径，也可能只填到 /v1，两种都接受且只补一次。
    final path = uri.path.endsWith(_chatPath)
        ? uri.path
        : uri.path.endsWith('/')
            ? '${uri.path}chat/completions'
            : '${uri.path}$_chatPath';
    return uri.replace(path: path);
  }

  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || trimmed.length > maxQuestionLength) {
      throw const AssistantException('请输入 1–1000 字的问题。');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _request(client, trimmed, context).timeout(timeout);
    } on AssistantException {
      rethrow;
    } on TimeoutException {
      throw const AssistantException('模型服务响应超时，请稍后重试或切回本地规则。');
    } on SocketException {
      throw const AssistantException('无法连接模型服务，请检查地址和网络。');
    } on HandshakeException {
      throw const AssistantException('模型服务证书验证失败，请检查服务地址。');
    } on FormatException {
      throw const AssistantException('模型服务返回格式不正确。');
    } on HttpException {
      throw const AssistantException('模型服务连接中断，请重试。');
    } finally {
      client.close(force: true);
    }
  }

  /// 所有失败分支都只说固定文案，绝不回显 Key 或上游响应体。
  Future<String> _request(
    HttpClient client,
    String question,
    AssistantContext context,
  ) async {
    final request = await client.postUrl(endpoint);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    request.write(
      jsonEncode({
        'model': model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': assistantSystemPrompt},
          {'role': 'user', 'content': assistantUserPayload(question, context)},
        ],
      }),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw AssistantException(switch (response.statusCode) {
        400 || 413 => '模型服务拒绝了请求，请检查模型名是否可用。',
        401 || 403 => 'API Key 无效，或该 Key 无权访问所选模型。',
        404 => '模型服务地址或模型名不正确，请检查后重试。',
        429 => '模型服务繁忙或额度不足，请稍后重试。',
        _ => '模型服务暂时不可用，请稍后重试或切回本地规则。',
      });
    }
    if (response.headers.contentType?.mimeType != 'application/json') {
      throw const AssistantException('模型服务返回格式不正确。');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const AssistantException('模型回复过长，请缩小问题范围后重试。');
      }
      bytes.addAll(chunk);
    }
    return _extractAnswer(jsonDecode(utf8.decode(bytes)));
  }

  static String _extractAnswer(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const AssistantException('模型服务返回格式不正确。');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AssistantException('模型服务没有返回回答。');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AssistantException('模型服务没有返回文字。');
    }
    return content.trim();
  }
}
