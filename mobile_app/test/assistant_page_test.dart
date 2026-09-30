import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/assistant_chat_store.dart';
import 'package:medication_device_app/assistant/assistant_credentials.dart';
import 'package:medication_device_app/assistant/assistant_page.dart';
import 'package:medication_device_app/assistant/assistant_provider.dart';
import 'package:medication_device_app/assistant/assistant_service.dart';
import 'package:medication_device_app/assistant/assistant_settings.dart';
import 'package:medication_device_app/assistant/assistant_tts.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';
import 'package:medication_device_app/assistant/models/chat_message.dart';

/// 内存聊天库：测试不碰平台通道，也方便断言「到底存了什么」。
class _MemoryChatStore implements AssistantChatStore {
  _MemoryChatStore([this.saved = const []]);

  List<ChatMessage> saved;
  int clears = 0;

  @override
  Future<List<ChatMessage>> load() async => saved;

  @override
  Future<void> save(List<ChatMessage> messages) async =>
      saved = List.of(messages);

  @override
  Future<void> clear() async {
    clears++;
    saved = const [];
  }
}

class _MemoryStore implements AssistantCredentialsStore {
  _MemoryStore([this.state = AssistantCredentialState.empty]);

  AssistantCredentialState state;

  @override
  Future<AssistantCredentialState> load() async => state;

  @override
  Future<void> save(AssistantCredentialState next) async => state = next;

  @override
  Future<void> clear() async => state = AssistantCredentialState.empty;
}

/// 固定回答：不联网，专门用来观察界面怎么标注来源。
class _FixedAnswer implements AssistantProvider {
  _FixedAnswer(this.answer);

  final String answer;

  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
    List<String> references = const [],
  }) async => answer;
}

/// 内存朗读引擎：记录读过的文本与停叫次数，不碰平台通道。
class _MemorySpeaker implements AssistantSpeaker {
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> dispose() async {}
}

/// 内存偏好库：测试断言「到底存了什么」。
class _MemorySettingsStore implements AssistantSettingsStore {
  _MemorySettingsStore([this.settings = AssistantSettings.defaults]);

  AssistantSettings settings;

  @override
  Future<AssistantSettings> load() async => settings;

  @override
  Future<void> save(AssistantSettings next) async => settings = next;
}

/// 逐块吐字的在线 provider：专门观察流式回答怎么落成一条消息，以及收到了哪些历史。
class _StreamingProvider implements StreamingAssistantProvider {
  _StreamingProvider(this.chunks, {this.gap = Duration.zero});

  final List<String> chunks;
  final Duration gap;
  List<ChatTurn> lastHistory = const [];

  @override
  Future<String> reply({
    required String question,
    required AssistantContext context,
    List<String> references = const [],
  }) async => chunks.join();

  @override
  Stream<String> replyStream({
    required String question,
    required AssistantContext context,
    List<String> references = const [],
    List<ChatTurn> history = const [],
  }) async* {
    lastHistory = List.of(history);
    for (final chunk in chunks) {
      if (gap > Duration.zero) await Future<void>.delayed(gap);
      yield chunk;
    }
  }
}

const _gateway = AssistantProfile(
  id: 'g1',
  name: '团队网关',
  mode: OnlineAssistantMode.gateway,
  endpoint: 'https://assistant.example.com/v1/assistant/chat',
  accessToken: 'gateway-code',
);

const _context = AssistantContext(
  todayCount: 2,
  last7DaysCount: 3,
  totalCount: 9,
  dailyCounts: [0, 1, 0, 0, 1, 0, 1],
);

/// 界面上的九个快捷问题，与 `_AssistantPageState._quickQuestions` 一一对应。
const _quickQuestions = [
  '今天用了几次？',
  '最近有异常吗？',
  '查看最近一周',
  '有什么建议？',
  '数据是最新的吗？',
  '设备时间对吗？',
  '一共有多少条记录？',
  '空白那几天怎么看？',
  '能问什么？',
];

Future<void> _pump(
  WidgetTester tester, {
  AssistantService? service,
  AssistantCredentialsStore? store,
  AssistantChatStore? chats,
  AssistantSpeaker? speaker,
  AssistantSettingsStore? settingsStore,
  Size size = const Size(420, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // viewInsets 同样是全局视图状态，框架不会替你还原，必须挂 tearDown。
  // 用例末尾手工还原是有条件的：用例在中途断言失败时那一行根本执行不到，
  // 剩下的用例就全都带着一个「键盘一直按着」的窗口跑——列表被压矮、
  // 懒构建的行不再被建出来，于是报出「状态没丢、却找不到那条消息」的假失败。
  addTearDown(() => tester.view.viewInsets = const FakeViewPadding());
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AssistantPage(
        service: service,
        store: store,
        chatStore: chats ?? _MemoryChatStore(),
        speaker: speaker,
        settingsStore: settingsStore,
        assistantContext: _context,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 输入并发送一条问题，等回答出现。
Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('键盘弹起时不再溢出，输入的字仍然看得见', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // 模拟键盘占掉 300 逻辑像素：修复前摘要卡是固定项，会顶出
    // BOTTOM OVERFLOWED BY ... PIXELS，输入框被挤出屏幕。
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '键盘测试');
    await tester.pumpAndSettle();
    expect(find.text('键盘测试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 收起键盘，免得影响同一文件里后面的用例。
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
  });

  testWidgets('大字号加键盘同时出现也不溢出', (tester) async {
    await _pump(tester, size: const Size(375, 812), textScale: 1.5);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
  });

  testWidgets('重新打开时读回本机历史，而不是从开场白开始', (tester) async {
    final chats = _MemoryChatStore([
      ChatMessage(
        role: ChatRole.user,
        text: '昨天问过的问题',
        createdAt: DateTime(2026, 9, 28),
      ),
      ChatMessage(
        role: ChatRole.assistant,
        text: '昨天得到的回答',
        createdAt: DateTime(2026, 9, 28),
        source: ChatSource.online,
      ),
    ]);

    await _pump(tester, chats: chats);

    expect(find.text('昨天问过的问题'), findsOneWidget);
    expect(find.text('昨天得到的回答'), findsOneWidget);
    expect(find.text('在线回答'), findsOneWidget);
  });

  testWidgets('本地回答与在线回答各自带来源标', (tester) async {
    await _pump(
      tester,
      service: AssistantService(provider: _FixedAnswer('近 7 天共 3 次。')),
    );
    await _ask(tester, '最近有异常吗？');
    expect(find.text('本地回答'), findsOneWidget);
    expect(find.textContaining('近 7 天共 3 次。'), findsOneWidget);
  });

  testWidgets('通用知识回答标成 AI 知识并补上「不是设备记录」', (tester) async {
    await _pump(
      tester,
      service: AssistantService(
        provider: _FixedAnswer('哮喘是一种慢性气道炎症。\n【来源】AI知识'),
        isRemote: true,
      ),
    );
    await _ask(tester, '介绍一下哮喘');

    expect(find.text('AI 知识'), findsOneWidget);
    expect(find.textContaining('不是你的设备记录'), findsOneWidget);
    // 标记行本身不显示给用户，来源用小标表达。
    expect(find.textContaining('【来源】'), findsNothing);
  });

  testWidgets('切换本地与在线：历史一条不少，只多一条分隔提示', (tester) async {
    final chats = _MemoryChatStore();
    final store = _MemoryStore(
      const AssistantCredentialState(profiles: [_gateway], selectedId: 'g1'),
    );
    await _pump(tester, store: store, chats: chats);

    await _ask(tester, '今天用了几次？');
    expect(find.textContaining('今天使用 2 次'), findsOneWidget);
    expect(find.text('本地回答'), findsOneWidget);
    expect(chats.saved, hasLength(3)); // 开场白 + 提问 + 回答

    await tester.tap(find.text('在线'));
    await tester.pumpAndSettle();
    // 关键：切过去之后本地那条回答还在——这正是以前会整段消失的地方。
    expect(find.textContaining('今天使用 2 次'), findsOneWidget);
    expect(find.textContaining('已启用在线助手'), findsOneWidget);
    expect(find.text('本地回答'), findsOneWidget);

    await tester.tap(find.text('本地'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今天使用 2 次'), findsOneWidget);
    expect(find.text('已切回本地摘要，不联网。'), findsOneWidget);
    expect(chats.saved, hasLength(5)); // 两次切换各插一条提示
  });

  testWidgets('清空对话会删掉本机历史，只留开场白', (tester) async {
    final chats = _MemoryChatStore();
    await _pump(tester, chats: chats);
    await _ask(tester, '随便问问');
    expect(chats.saved, hasLength(3));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(chats.clears, 1);
    expect(chats.saved, hasLength(1));
    expect(find.textContaining('随便问问'), findsNothing);
  });

  testWidgets('取消清空时什么都不动', (tester) async {
    final chats = _MemoryChatStore();
    // 视口给足高度：列表是懒构建的，滚出视口（连同 250 逻辑像素的缓存区）的
    // 行压根不会被建出来。这条用例问的是「取消后对话还在不在」，不该顺带
    // 依赖滚动位置，否则它在「回答恰好很长」时会给出误导性的红。
    await _pump(tester, chats: chats, size: const Size(420, 1400));
    await _ask(tester, '随便问问');

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(chats.clears, 0);
    expect(chats.saved, hasLength(3));
    expect(find.textContaining('随便问问'), findsOneWidget);
  });

  testWidgets('「更多」菜单只有对话与朗读三项，不再有外观切换', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('清空对话'), findsOneWidget);
    expect(find.text('带上本轮对话'), findsOneWidget);
    expect(find.text('朗读设置'), findsOneWidget);
    // 外观切换（跟随系统 / 浅色 / 深色）已按需求移除。前面三条正数断言先保证
    // 菜单真的展开了，这一条才有意义（单写 findsNothing 在菜单根本没开时也会通过）。
    expect(find.textContaining('外观：'), findsNothing);
  });

  testWidgets('快捷问题每个都能在本地拿到答案，不落到兜底', (tester) async {
    await _pump(tester);
    expect(find.byType(ActionChip), findsNWidgets(_quickQuestions.length));

    for (final question in _quickQuestions) {
      final chip = find.widgetWithText(ActionChip, question);
      // 后面的问题是横向滚出去的，先滚进视口再点。
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('本地模式只按固定规则解释你的记录'),
        findsNothing,
        reason: '「$question」落到了兜底，说明没有对应的规则分支',
      );
    }
  });

  testWidgets('助手回答可以朗读，读的是回答正文', (tester) async {
    final speaker = _MemorySpeaker();
    await _pump(
      tester,
      service: AssistantService(provider: _FixedAnswer('近 7 天共 3 次。')),
      speaker: speaker,
    );
    await _ask(tester, '最近有异常吗？');

    // 开场白和回答都是助手气泡，各带一个「朗读」；取最后一个 = 最新回答。
    await tester.tap(find.text('朗读').last);
    await tester.pumpAndSettle();
    expect(speaker.spoken, hasLength(1));
    expect(speaker.spoken.first, contains('近 7 天共 3 次'));
  });

  testWidgets('在线流式回答逐字滚出，结束后落成带来源标的回答', (tester) async {
    await _pump(
      tester,
      service: AssistantService(
        provider: _StreamingProvider(
          ['近 7 天共 ', '3 次使用动作。'],
          gap: const Duration(milliseconds: 100),
        ),
        isRemote: true,
      ),
    );
    await tester.enterText(find.byType(TextField), '最近怎么样');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // 第一块已到、流还没结束：能看到滚动的部分文本和「正在输出」。
    expect(find.text('正在输出'), findsOneWidget);
    expect(find.textContaining('近 7 天共'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.textContaining('近 7 天共 3 次使用动作。'), findsOneWidget);
    expect(find.text('在线回答'), findsOneWidget);
    expect(find.text('正在输出'), findsNothing);
  });

  testWidgets('开启自动朗读后新回答自动朗读，新问题会先停掉上一段', (tester) async {
    final speaker = _MemorySpeaker();
    await _pump(
      tester,
      service: AssistantService(provider: _FixedAnswer('近 7 天共 3 次。')),
      speaker: speaker,
      settingsStore: _MemorySettingsStore(
        const AssistantSettings(autoSpeak: true),
      ),
    );
    await _ask(tester, '最近有异常吗？');
    expect(speaker.spoken, hasLength(1));
    expect(speaker.spoken.first, contains('近 7 天共 3 次'));
    // 提问开始与朗读开始各会停一次上一段，保证「只读最新一句」。
    expect(speaker.stops, greaterThanOrEqualTo(1));
  });

  testWidgets('「带上本轮对话」开关落盘，开启后流式请求带上历史', (tester) async {
    final settings = _MemorySettingsStore();
    final provider = _StreamingProvider(['近 7 天共 3 次。']);
    await _pump(
      tester,
      service: AssistantService(provider: provider, isRemote: true),
      settingsStore: settings,
    );

    // 默认关：第一问不带历史。
    await _ask(tester, '最近有异常吗？');
    expect(provider.lastHistory, isEmpty);
    expect(settings.settings.sendHistory, isFalse);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('带上本轮对话'));
    await tester.pumpAndSettle();
    expect(settings.settings.sendHistory, isTrue);

    // 再问一条，应把上一轮问答带出去。
    await _ask(tester, '那今天呢？');
    expect(provider.lastHistory, isNotEmpty);
  });
}
