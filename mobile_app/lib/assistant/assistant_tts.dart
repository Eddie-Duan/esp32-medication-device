import 'package:flutter_tts/flutter_tts.dart';

/// 朗读回答的抽象，便于测试注入假实现（平台通道在测试里不可用）。
abstract class AssistantSpeaker {
  Future<void> speak(String text);
  Future<void> stop();

  /// 语速，flutter_tts 取值 0.0–1.0（0.5 为正常）。
  Future<void> setRate(double rate);

  /// 音调，flutter_tts 取值 0.5–2.0（1.0 为正常）。
  Future<void> setPitch(double pitch);

  Future<void> dispose();
}

/// Android 系统 TTS：离线、免费、语音不出手机，与「Key 不出手机」同一隐私立场。
///
/// 失败不抛异常到 UI：设备没装 TTS 引擎或初始化失败时，speak 静默失败，
/// 由调用方决定要不要提示用户。这里不读、不写任何凭据，也不上传文本。
class SystemTtsSpeaker implements AssistantSpeaker {
  final FlutterTts _tts = FlutterTts();

  double _rate = 0.5;
  double _pitch = 1.0;

  @override
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // 每次读前设定语言与语速/音调，兼容设备默认引擎是英文、或用户调过的情况。
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(_rate);
    await _tts.setPitch(_pitch);
    await _tts.speak(trimmed);
  }

  @override
  Future<void> setRate(double rate) async => _rate = rate;

  @override
  Future<void> setPitch(double pitch) async => _pitch = pitch;

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() => _tts.stop();
}
