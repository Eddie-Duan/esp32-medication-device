import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// 朗读回答的抽象，便于测试注入假实现（平台通道在测试里不可用）。
abstract class AssistantSpeaker {
  /// 朗读 [text]。
  ///
  /// 返回的 Future **读完才完成**（被 [stop]、引擎报错也完成）。界面的
  /// 「朗读 / 停止」按钮靠它判断什么时候收回状态——`FlutterTts.speak` 本身在
  /// Android 上是立刻返回的，不能当读完信号用。
  ///
  /// [onProgress] 回报「已读到的字符下标（不含）」。引擎不支持进度回报时不会
  /// 回调，界面就只是没有灰色高亮，不影响朗读本身。
  Future<void> speak(String text, {void Function(int endOffset)? onProgress});

  Future<void> stop();

  /// 语速，flutter_tts 取值 0.0–1.0（0.5 为正常）。
  Future<void> setRate(double rate);

  /// 音调，flutter_tts 取值 0.5–2.0（1.0 为正常）。
  Future<void> setPitch(double pitch);

  Future<void> dispose();
}

/// Android 系统 TTS：离线、免费、语音不出手机，与「Key 加密保存在手机、不经过团队服务器」同一隐私立场。
///
/// 这里不读、不写任何凭据，也不上传文本。失败语义：初始化或朗读失败时 [speak]
/// 返回的 Future 以错误完成，由调用方决定怎么提示用户。
class SystemTtsSpeaker implements AssistantSpeaker {
  final FlutterTts _tts = FlutterTts();

  double _rate = 0.5;
  double _pitch = 1.0;

  /// 当前这一句的「读完」信号。引擎只回报完成/取消/出错三种事件，这里把它们
  /// 翻译成一个 Future 交给调用方。
  Completer<void>? _utterance;

  @override
  Future<void> speak(String text, {void Function(int endOffset)? onProgress}) {
    if (text.isEmpty) return Future<void>.value();
    // 上一句若还挂着，先收尾，免得两个信号叠在一起。
    _finishUtterance();
    final done = Completer<void>();
    _utterance = done;

    // 读完、被停、出错都必须收尾：否则界面会一直停在「停止」状态。
    _tts.setCompletionHandler(_finishUtterance);
    _tts.setCancelHandler(_finishUtterance);
    _tts.setErrorHandler((_) => _finishUtterance(StateError('TTS 引擎报错')));
    if (onProgress != null) {
      // 按「已读到的字符下标」回报（Android 26+ 与 iOS 的 speech marks）。
      // 不支持的引擎不会触发这个回调，界面退化成没有高亮。
      _tts.setProgressHandler((_, _, end, _) => onProgress(end));
    }
    unawaited(_startUtterance(text));
    return done.future;
  }

  Future<void> _startUtterance(String text) async {
    try {
      // 每次读前设定语言与语速/音调，兼容设备默认引擎是英文、或用户调过的情况。
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
      await _tts.speak(text);
    } catch (error) {
      // 引擎缺失或初始化失败：立刻让调用方拿到错误去提示，而不是一直等下去。
      _finishUtterance(error);
    }
  }

  void _finishUtterance([Object? error]) {
    final done = _utterance;
    _utterance = null;
    if (done == null || done.isCompleted) return;
    if (error != null) {
      done.completeError(error);
    } else {
      done.complete();
    }
  }

  @override
  Future<void> setRate(double rate) async => _rate = rate;

  @override
  Future<void> setPitch(double pitch) async => _pitch = pitch;

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } finally {
      // 有的引擎停止时不再回报取消事件，这里兜底，保证「停止」一定会收尾。
      _finishUtterance();
    }
  }

  @override
  Future<void> dispose() => stop();
}
