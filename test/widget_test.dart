import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/models/app_state.dart';
import 'package:local_ai_app/models/conversation.dart';
import 'package:local_ai_app/services/stt_service.dart';
import 'package:local_ai_app/services/tts_service.dart';

class FakeSttService implements SttService {
  @override
  Future<bool> initialize() async => true;

  @override
  bool get isListening => false;

  @override
  bool get isAvailable => true;

  @override
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onDone,
    String? localeId,
  }) async {}

  @override
  Future<void> stopListening() async {}
}

class FakeTtsService implements TtsService {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  Function(String)? _onError;

  bool _isSpeaking = false;
  List<String> spokenTexts = [];
  bool wasStopCalled = false;

  @override
  Future<void> initialize() async {}

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  void setHandlers({
    VoidCallback? onStart,
    VoidCallback? onComplete,
    Function(String)? onError,
  }) {
    _onStart = onStart;
    _onComplete = onComplete;
    _onError = onError;
  }

  @override
  Future<void> speak(String text) async {
    _isSpeaking = true;
    spokenTexts.add(text);
    if (_onStart != null) {
      _onStart!();
    }
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    wasStopCalled = true;
  }

  void triggerComplete() {
    _isSpeaking = false;
    if (_onComplete != null) {
      _onComplete!();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppState instantiation unit test', () {
    final appState = AppState(
      sttService: FakeSttService(),
      ttsService: FakeTtsService(),
    );
    expect(appState.activeScreen, AppScreen.chat);
    expect(appState.isLoading, true);
    expect(appState.isStreaming, false);
  });

  group('TTS and Session ID Invalidation Tests', () {
    late AppState appState;
    late FakeTtsService fakeTts;
    late FakeSttService fakeStt;

    setUp(() {
      fakeTts = FakeTtsService();
      fakeStt = FakeSttService();
      appState = AppState(sttService: fakeStt, ttsService: fakeTts);
    });

    test('Initial state of TTS', () {
      expect(appState.isTtsEnabled, true);
      expect(appState.isSpeaking, false);
      expect(appState.ttsState, TtsState.idle);
    });

    test('Speak message processes and enqueues sentences', () async {
      final msg = Message(
        sender: 'ai',
        text: 'This is the first sentence. This is the second!',
        timestamp: DateTime.now(),
      );

      await appState.speakMessage(msg);

      expect(appState.isSpeaking, true);
      expect(appState.ttsState, TtsState.speaking);
      expect(fakeTts.spokenTexts.length, 1);
      expect(fakeTts.spokenTexts.first, 'This is the first sentence.');

      // Complete first sentence
      fakeTts.triggerComplete();

      // Second sentence should play
      expect(fakeTts.spokenTexts.length, 2);
      expect(fakeTts.spokenTexts.last, 'This is the second!');
    });

    test('Stop speaking invalidates session ID and clears queue', () async {
      final msg = Message(
        sender: 'ai',
        text: 'First sentence. Second sentence.',
        timestamp: DateTime.now(),
      );

      await appState.speakMessage(msg);
      expect(fakeTts.spokenTexts.first, 'First sentence.');

      // Stop
      await appState.stopSpeaking();
      expect(appState.isTtsEnabled, false);
      expect(appState.isSpeaking, false);
      expect(appState.ttsState, TtsState.stopped);
      expect(appState.currentlySpeakingMessage, isNull);

      // Trigger completion of first sentence, should not play second
      fakeTts.triggerComplete();
      expect(fakeTts.spokenTexts.length, 1); // No new text enqueued/spoken
    });

    test('Mute cancels active utterance and ignores callbacks', () async {
      final msg = Message(
        sender: 'ai',
        text: 'Hello world. How are you?',
        timestamp: DateTime.now(),
      );

      await appState.speakMessage(msg);
      expect(fakeTts.spokenTexts.first, 'Hello world.');

      // Mute
      await appState.muteTts(reason: 'Muted');
      expect(appState.isTtsEnabled, false);
      expect(appState.isSpeaking, false);
      expect(appState.ttsState, TtsState.muted);

      // Complete first sentence
      fakeTts.triggerComplete();
      expect(fakeTts.spokenTexts.length, 1); // Second sentence ignored
    });
  });
}
