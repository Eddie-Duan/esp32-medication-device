import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 品牌种子色。[buildLightTheme] 与 [buildDarkTheme] 都从它派生，
/// 深浅两套主题因此共享同一组配色关系（同一色相、同一层级）。
const _seedColor = Color(0xff147d79);

/// 浅色主题。只在 `main.dart` 里装配，页面不要再写死颜色。
ThemeData buildLightTheme() => _themeFor(Brightness.light);

/// 深色主题。
ThemeData buildDarkTheme() => _themeFor(Brightness.dark);

ThemeData _themeFor(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // 背景与 AppBar 都取自 colorScheme，不再写死 0xfff5f7f8：
    // 写死的话深色模式下背景仍是浅灰，整页会花。
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      centerTitle: false,
    ),
  );
}

/// 「跟随系统 / 浅色 / 深色」三态控制器。
///
/// 不做成全局单例：全局可变状态会在测试之间泄漏。由 `MedicationDeviceApp`
/// 持有一份，需要读写的地方通过构造参数拿到它。
class AppThemeController {
  AppThemeController({ThemeMode initial = ThemeMode.system})
    : mode = ValueNotifier(initial);

  /// 持久化用的 key。改名会让用户丢一次外观设置，不值得，所以别动。
  static const _key = 'app.theme_mode';

  /// 当前模式。UI 用 `ValueListenableBuilder` 监听它，改了就整棵树重建。
  final ValueNotifier<ThemeMode> mode;

  /// 启动时读一次；读不出来就用默认（跟随系统），不打断启动。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = parseThemeMode(prefs.getString(_key));
    } catch (_) {
      // 存储不可用时保持默认值。
    }
  }

  /// 切换并落盘。落盘失败只影响下次启动的默认值，本次切换已经生效。
  Future<void> setMode(ThemeMode next) async {
    mode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next.name);
    } catch (_) {
      // 同上，静默降级。
    }
  }

  void dispose() => mode.dispose();
}

/// 存档里的字符串 → [ThemeMode]。认不出来（含 null 与旧版本残留）都表示跟随系统。
ThemeMode parseThemeMode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};
