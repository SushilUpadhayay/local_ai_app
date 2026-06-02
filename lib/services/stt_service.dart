import 'dart:async';

abstract class SttService {
  Future<void> initialize();
  Future<void> startListening({required Function(String text) onResult});
  Future<void> stopListening();
  bool get isListening;
}

class WhisperSttService implements SttService {
  bool _isListening = false;
  
  @override
  bool get isListening => _isListening;

  @override
  Future<void> initialize() async {
    // Placeholder: In the future, load native whisper.cpp model/context here
  }

  @override
  Future<void> startListening({required Function(String text) onResult}) async {
    _isListening = true;
    
    // Simulate Whisper.cpp speech-to-text decoding
    await Future.delayed(const Duration(milliseconds: 2000));
    if (_isListening) {
      final simulatedTranscriptions = [
        "Explain quantum computing simply.",
        "How do I clear Dart memory?",
        "Write a quick Dart function.",
        "What is on-device LLM inference?"
      ];
      final index = DateTime.now().millisecond % simulatedTranscriptions.length;
      onResult(simulatedTranscriptions[index]);
    }
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
  }
}
