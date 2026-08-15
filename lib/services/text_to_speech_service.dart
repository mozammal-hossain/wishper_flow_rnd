import 'package:flutter_tts/flutter_tts.dart';

abstract class TextToSpeechService {
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTextToSpeechService implements TextToSpeechService {
  FlutterTextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}
