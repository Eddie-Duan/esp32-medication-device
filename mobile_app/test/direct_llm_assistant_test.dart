import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/assistant_exception.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';
import 'package:medication_device_app/assistant/providers/direct_llm_assistant_provider.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  const context = AssistantContext(
    todayCount: 2,
    last7DaysCount: 8,
    isDemo: true,
    totalCount: 21,
    dailyCounts: [0, 1, 0, 2, 0, 0, 5],
  );

  DirectLlmAssistantProvider providerFor(String baseUrl) =>
      DirectLlmAssistantProvider(
        baseUrl: baseUrl,
        apiKey: 'user-private-key',
        model: 'user-model',
      );

  test('only https, or explicit loopback http, is accepted', () {
    for (final address in [
      'http://example.com/v1',
      'api.deepseek.com/v1',
      'https://token@example.com/v1',
      'https://example.com/v1?key=secret',
      'https://example.com/v1#fragment',
    ]) {
      expect(
        () => DirectLlmAssistantProvider(
          baseUrl: address,
          apiKey: 'k',
          model: 'm',
        ),
        throwsA(isA<AssistantException>()),
      );
    }
    expect(
      () => DirectLlmAssistantProvider(
        baseUrl: 'http://127.0.0.1:11434/v1',
        apiKey: 'k',
        model: 'm',
        allowLocalHttp: false,
      ),
      throwsA(isA<AssistantException>()),
    );
  });

  test('the chat completions path is appended exactly once', () {
    expect(
      providerFor('https://api.example.com/v1/').endpoint.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      providerFor('https://api.example.com/v1').endpoint.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      providerFor('https://api.example.com/v1/chat/completions')
          .endpoint
          .toString(),
      'https://api.example.com/v1/chat/completions',
    );
  });

  Future<void> withServer(
    Future<void> Function(HttpRequest) handler,
    Future<void> Function(String) use,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) => unawaited(handler(request)));
    try {
      // Widget binding installs a fake HTTP client globally; these contract
      // tests intentionally use a real loopback socket in this zone only.
      await HttpOverrides.runWithHttpOverrides(
        () => use('http://127.0.0.1:${server.port}/v1'),
        _LoopbackHttpOverrides(),
      );
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  }

  test('the request carries the user key and the answer comes back trimmed',
      () async {
    await withServer(
      (request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer user-private-key',
        );
        final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(data['model'], 'user-model');
        expect(data['temperature'], 0);
        final messages = data['messages'] as List;
        expect(messages, hasLength(2));
        expect((messages[0] as Map)['role'], 'system');
        expect((messages[0] as Map)['content'], contains('不要诊断'));
        expect((messages[1] as Map)['role'], 'user');
        expect(
          jsonDecode((messages[1] as Map)['content'] as String)['context'],
          context.toJson(),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '  近 7 天共 8 次使用动作。  '},
              },
            ],
          }),
        );
        await request.response.close();
      },
      (baseUrl) async {
        final answer = await providerFor(baseUrl)
            .reply(question: '最近怎么样？', context: context);
        expect(answer, '近 7 天共 8 次使用动作。');
      },
    );
  });

  test('failures never leak the key or the upstream body', () async {
    for (final status in [400, 401, 403, 404, 429, 500]) {
      await withServer(
        (request) async {
          request.response.statusCode = status;
          request.response.write('echo-of-private-key user-private-key');
          await request.response.close();
        },
        (baseUrl) async {
          try {
            await providerFor(baseUrl)
                .reply(question: '次数？', context: context);
            fail('Expected a sanitized failure for $status');
          } on AssistantException catch (error) {
            expect(error.message, isNot(contains('user-private-key')));
            expect(error.message, isNot(contains('echo-of-private-key')));
          }
        },
      );
    }
  });

  test('empty credentials are rejected when the provider is built', () {
    expect(
      () => DirectLlmAssistantProvider(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '   ',
        model: 'm',
      ),
      throwsA(
        isA<AssistantException>().having(
          (error) => error.message,
          'message',
          contains('API Key'),
        ),
      ),
    );
    expect(
      () => DirectLlmAssistantProvider(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: '  ',
      ),
      throwsA(
        isA<AssistantException>().having(
          (error) => error.message,
          'message',
          contains('模型名称'),
        ),
      ),
    );
  });

  test('malformed, empty and oversized answers fail without a fallback',
      () async {
    for (final body in [
      'not json',
      '{"choices":[]}',
      '{"choices":[{"message":{"content":"   "}}]}',
      jsonEncode({
        'choices': [
          {
            'message': {'content': 'x' * 66000},
          },
        ],
      }),
    ]) {
      await withServer(
        (request) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(body);
          await request.response.close();
        },
        (baseUrl) async {
          await expectLater(
            providerFor(baseUrl).reply(question: '次数？', context: context),
            throwsA(isA<AssistantException>()),
          );
        },
      );
    }
  });

  test('streaming parses SSE data lines into ordered chunks', () async {
    await withServer(
      (request) async {
        final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(data['stream'], true);
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write('data: {"choices":[{"delta":{"content":"近 7 天"}}]}\n\n');
        request.response.write('data: {"choices":[{"delta":{"content":"共 8 次。"}}]}\n\n');
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      },
      (baseUrl) async {
        final chunks = await providerFor(baseUrl)
            .replyStream(question: '最近怎么样？', context: context)
            .toList();
        expect(chunks, ['近 7 天', '共 8 次。']);
      },
    );
  });

  test('streaming falls back to one chunk when the server returns plain JSON',
      () async {
    await withServer(
      (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '近 7 天共 8 次使用动作。'},
              },
            ],
          }),
        );
        await request.response.close();
      },
      (baseUrl) async {
        final chunks = await providerFor(baseUrl)
            .replyStream(question: '最近怎么样？', context: context)
            .toList();
        expect(chunks, ['近 7 天共 8 次使用动作。']);
      },
    );
  });

  test('streaming sends multi-turn history as messages before the question',
      () async {
    await withServer(
      (request) async {
        final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final messages = data['messages'] as List;
        expect(messages, hasLength(4));
        expect((messages[0] as Map)['role'], 'system');
        expect((messages[0] as Map)['content'], contains('更早的几轮问答'));
        expect((messages[1] as Map), {'role': 'user', 'content': '上一条问题'});
        expect((messages[2] as Map), {
          'role': 'assistant',
          'content': '上一条回答',
        });
        expect((messages[3] as Map)['role'], 'user');
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      },
      (baseUrl) async {
        await providerFor(baseUrl)
            .replyStream(
              question: '那今天呢？',
              context: context,
              history: const [
                (role: 'user', text: '上一条问题'),
                (role: 'assistant', text: '上一条回答'),
              ],
            )
            .drain<void>();
      },
    );
  });
}
