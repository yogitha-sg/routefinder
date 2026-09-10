import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();

  bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> init() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  Future<void> speak(String text) async {
    if (!_enabled || text.trim().isEmpty) return;

    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;

    if (!value) {
      await _tts.stop();
    }
  }
}