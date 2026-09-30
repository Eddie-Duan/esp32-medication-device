import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('深浅两套主题的亮度正确，且都开着 Material 3', () {
    expect(buildLightTheme().brightness, Brightness.light);
    expect(buildDarkTheme().brightness, Brightness.dark);
    expect(buildLightTheme().useMaterial3, isTrue);
    expect(buildDarkTheme().useMaterial3, isTrue);
  });

  test('两套主题不再写死浅色背景', () {
    // 写死 0xfff5f7f8 的话，深色模式下整页会是浅灰底配浅字。
    expect(
      buildDarkTheme().scaffoldBackgroundColor,
      buildDarkTheme().colorScheme.surface,
    );
    expect(
      buildLightTheme().appBarTheme.backgroundColor,
      buildLightTheme().colorScheme.surface,
    );
  });

  test('存档值解析：认不出来就跟随系统', () {
    expect(parseThemeMode('light'), ThemeMode.light);
    expect(parseThemeMode('dark'), ThemeMode.dark);
    expect(parseThemeMode('system'), ThemeMode.system);
    expect(parseThemeMode(null), ThemeMode.system);
    expect(parseThemeMode('深色'), ThemeMode.system);
  });

  test('切换先改内存，存储不可用也照样生效', () async {
    final controller = AppThemeController();
    addTearDown(controller.dispose);
    expect(controller.mode.value, ThemeMode.system);

    // 测试环境没有平台通道，落盘会失败；本次切换必须已经生效。
    await controller.setMode(ThemeMode.dark);
    expect(controller.mode.value, ThemeMode.dark);
    await controller.setMode(ThemeMode.light);
    expect(controller.mode.value, ThemeMode.light);

    // 读存档失败或本来就没存档，都不该抛异常，也不会变成别的模式。
    await controller.load();
    expect(controller.mode.value, isIn([ThemeMode.light, ThemeMode.system]));
  });
}
