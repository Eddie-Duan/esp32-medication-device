import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/assistant_exception.dart';
import 'package:medication_device_app/assistant/assistant_page.dart';
import 'package:medication_device_app/assistant/assistant_provider.dart';
import 'package:medication_device_app/assistant/assistant_service.dart';
import 'package:medication_device_app/assistant/assistant_settings_dialog.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';
import 'package:medication_device_app/assistant/providers/gateway_assistant_provider.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

class _RemoteFailure implements AssistantProvider {
  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
  }) async => throw const AssistantException('在线助手响应超时，请稍后重试或切回本地摘要。');
}

void main() {
  const context = AssistantContext(
    todayCount: 2,
    last7DaysCount: 8,
    isDemo: true,
  );

  test('HTTPS is required outside explicit loopback debug transport', () {
    for (final address in [
      'http://example.com/v1/assistant/chat',
      'https://secret@example.com/v1/assistant/chat',
      'https://example.com/v1/assistant/chat?token=secret',
      'wss://example.com/xiaozhi/v1/',
    ]) {
      expect(
        () => GatewayAssistantProvider(endpoint: address),
        throwsA(isA<AssistantException>()),
      );
    }
    expect(
      () => GatewayAssistantProvider(
        endpoint: 'http://127.0.0.1:8787/v1/assistant/chat',
        allowLocalHttp: false,
      ),
      throwsA(isA<AssistantException>()),
    );
  });

  Future<void> withServer(
    Future<void> Function(HttpRequest) handler,
    Future<void> Function(String) use,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(
      (request) => unawaited(handler(request)),
    );
    try {
      // Widget binding installs a fake HTTP client globally. These contract
      // tests intentionally use a real loopback socket in this zone only.
      await HttpOverrides.runWithHttpOverrides(
        () => use('http://127.0.0.1:${server.port}/v1/assistant/chat'),
        _LoopbackHttpOverrides(),
      );
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  }

  test(
    'wire request contains fresh summary and auth, response is explicitly marked mock',
    () async {
      await withServer(
        (request) async {
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer gateway-code',
          );
          final data =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(data.keys.toSet(), {'schema_version', 'question', 'context'});
          expect(data['context'], context.toJson());
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'schema_version': 1,
              'answer': '演示回复',
              'provider': 'mock',
            }),
          );
          await request.response.close();
        },
        (endpoint) async {
          final provider = GatewayAssistantProvider(
            endpoint: endpoint,
            accessToken: 'gateway-code',
          );
          final answer = await provider.reply(
            question: '最近记录？',
            context: context,
          );
          expect(answer, contains('尚未调用小智'));
          expect(answer, contains('演示回复'));
        },
      );
    },
  );

  test(
    'HTTP auth errors do not expose upstream payloads and redirects are not followed',
    () async {
      for (final status in [401, 302, 502]) {
        var requests = 0;
        await withServer(
          (request) async {
            requests++;
            request.response.statusCode = status;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              '/another-path',
            );
            request.response.write('private-upstream-token');
            await request.response.close();
          },
          (endpoint) async {
            try {
              await GatewayAssistantProvider(
                endpoint: endpoint,
              ).reply(question: '次数？', context: context);
              fail('Expected sanitized failure');
            } on AssistantException catch (error) {
              expect(error.message, isNot(contains('private-upstream-token')));
            }
            expect(requests, 1);
          },
        );
      }
    },
  );

  test(
    'invalid, empty and oversized JSON responses fail without a local fallback',
    () async {
      for (final body in [
        'not json',
        '{"answer":""}',
        jsonEncode({
          'schema_version': 1,
          'provider': 'xiaozhi',
          'answer': 'x' * 66000,
        }),
      ]) {
        await withServer(
          (request) async {
            request.response.headers.contentType = ContentType.json;
            request.response.write(body);
            await request.response.close();
          },
          (endpoint) async {
            await expectLater(
              GatewayAssistantProvider(
                endpoint: endpoint,
              ).reply(question: '次数？', context: context),
              throwsA(isA<AssistantException>()),
            );
          },
        );
      }
    },
  );

  test('total timeout covers a server that never responds', () async {
    await withServer((request) async {}, (endpoint) async {
      await expectLater(
        GatewayAssistantProvider(
          endpoint: endpoint,
          timeout: const Duration(milliseconds: 70),
        ).reply(question: '次数？', context: context),
        throwsA(
          isA<AssistantException>().having(
            (error) => error.message,
            'message',
            contains('超时'),
          ),
        ),
      );
    });
  });

  testWidgets('online setup requires consent before enabling a gateway', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantSettingsDialog())),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '启用在线助手'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('启用在线助手'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入完整的网关地址'), findsOneWidget);
  });

  testWidgets(
    'remote errors remain visible and never masquerade as local answers',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            service: AssistantService(
              provider: _RemoteFailure(),
              isRemote: true,
            ),
          ),
        ),
      );
      expect(find.text('在线'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '今天用了几次？'));
      await tester.pumpAndSettle();
      expect(find.textContaining('在线助手响应超时'), findsOneWidget);
      await tester.tap(find.byTooltip('回答方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本地摘要'));
      await tester.pumpAndSettle();
      expect(find.text('本地'), findsOneWidget);
      expect(find.text('已切回本地摘要，不联网。'), findsOneWidget);
    },
  );
}
