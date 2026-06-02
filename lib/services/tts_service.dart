import 'dart:async';

abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  bool get isSpeaking;
}

class PiperTtsService implements TtsService {
  bool _isSpeaking = false;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> initialize() async {
    // Placeholder: In the future, load native Piper TTS voices/models here
  }

  @override
  Future<void> speak(String text) async {
    _isSpeaking = true;
    
    // Simulate Piper TTS speaking duration based on length
    final durationMs = (text.split(' ').length * 300).clamp(1000, 5000);
    await Future.delayed(Duration(milliseconds: durationMs));
    _isSpeaking = false;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
  }
}
