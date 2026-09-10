import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();

  bool _enabled = true;

  bool get enabled => _enabled;

  // Initialize voice settings
  Future<void> init() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // Optional callbacks
    _tts.setStartHandler(() {
      print('Voice started');
    });

    _tts.setCompletionHandler(() {
      print('Voice completed');
    });

    _tts.setErrorHandler((message) {
      print('Voice error: $message');
    });
  }

  // Speak text
  Future<void> speak(String text) async {
    if (!_enabled) return;

    if (text.trim().isEmpty) return;

    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      print('TTS speak error: $e');
    }
  }

  // Stop speaking
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      print('TTS stop error: $e');
    }
  }

  // Enable / disable voice
  Future<void> setEnabled(bool value) async {
    _enabled = value;

    if (!value) {
      await stop();
    }
  }

  // Check whether TTS is available
  Future<bool> isAvailable() async {
    try {
      final result = await _tts.isLanguageAvailable('en-IN');

      return result == 1 || result == 0;
    } catch (e) {
      print('TTS availability error: $e');
      return false;
    }
  }
}