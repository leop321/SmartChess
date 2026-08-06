import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _flutterTts.setLanguage("en-US");
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _initialized = true;
      debugPrint('[TTSService] Initialized successfully');
    } catch (e) {
      debugPrint('[TTSService] Init error: $e');
    }
  }

  Future<void> speak(String text,
      {required bool enabled,
      required double rate,
      required double pitch}) async {
    if (!enabled) {
      debugPrint('[TTSService] speak() skipped — TTS disabled');
      return;
    }
    try {
      if (!_initialized) {
        await init();
      }
      debugPrint('[TTSService] Speaking: "$text" (rate=$rate, pitch=$pitch)');
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.setPitch(pitch);
      // On Android, calling stop() immediately before speak() can
      // race-condition the TTS engine reset. Skip stop() when not speaking.
      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      _isSpeaking = true;
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[TTSService] speak() error: $e');
    }
  }

  Future<void> stop() async {
    try {
      _isSpeaking = false;
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('[TTSService] stop() error: $e');
    }
  }
}
