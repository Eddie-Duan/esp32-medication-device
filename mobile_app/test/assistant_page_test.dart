import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/assistant/assistant_chat_store.dart';
import 'package:medication_device_app/assistant/assistant_credentials.dart';
import 'package:medication_device_app/assistant/assistant_page.dart';
import 'package:medication_device_app/assistant/assistant_provider.dart';
import 'package:medication_device_app/assistant/assistant_service.dart';
import 'package:medication_device_app/assistant/models/assistant_context.dart';
import 'package:medication_device_app/assistant/models/chat_message.dart';
import 'package:medication_device_app/theme/app_theme.dart';

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
  }) async => answer;
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

/// 界面上的八个快捷问题，与 `_AssistantPageState._quickQuestions` 一一对应。
const _quickQuestions = [
  '今天用了几次？',
  '最近有异常吗？',
  '查看最近一周',
  '有什么建议？',
  '数据是最新的吗？',
  '设备时间对吗？',
  '一共有多少条记录？',
  '空白那几天怎么看？',
];

Future<void> _pump(
  WidgetTester tester, {
  AssistantService? service,
  AssistantCredentialsStore? store,
  AssistantChatStore? chats,
  AppThemeController? theme,
  Size size = const Size(420, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        themeController: theme,
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
    await _pump(tester, chats: chats);
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

  testWidgets('有外观控制器时菜单给三档，切换落到控制器', (tester) async {
    final theme = AppThemeController();
    addTearDown(theme.dispose);
    await _pump(tester, theme: theme);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.textContaining('外观：'), findsNWidgets(3));

    await tester.tap(find.text('外观：深色'));
    await tester.pumpAndSettle();
    expect(theme.mode.value, ThemeMode.dark);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观：跟随系统'));
    await tester.pumpAndSettle();
    expect(theme.mode.value, ThemeMode.system);
  });

  testWidgets('没有外观控制器时不显示点了没反应的菜单项', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('清空对话'), findsOneWidget);
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
}
