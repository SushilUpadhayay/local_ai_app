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

  group('AppState getDerivedContextFromHistory tests', () {
    late AppState appState;

    setUp(() {
      appState = AppState(
        sttService: FakeSttService(),
        ttsService: FakeTtsService(),
      );
    });

    test('should return null when there are no messages', () {
      final derived = appState.getDerivedContextFromHistory([]);
      expect(derived['trekId'], isNull);
      expect(derived['tool'], isNull);
    });

    test(
      'should return null (No Prior Tool Execution) when there are only chat-only responses',
      () {
        final messages = [
          Message(sender: 'user', text: 'Hello', timestamp: DateTime.now()),
          Message(
            sender: 'ai',
            text: 'Hi, how can I help you?',
            timestamp: DateTime.now(),
            reasoningTrace: null,
          ),
          Message(
            sender: 'user',
            text: 'How are you?',
            timestamp: DateTime.now(),
          ),
          Message(
            sender: 'ai',
            text: 'I am an AI assistant.',
            timestamp: DateTime.now(),
            reasoningTrace: null,
          ),
        ];

        final derived = appState.getDerivedContextFromHistory(messages);
        expect(derived['trekId'], isNull);
        expect(derived['tool'], isNull);
      },
    );

    test('should return last valid resolved trek and tool', () {
      final messages = [
        Message(
          sender: 'user',
          text: 'Tell me about EBC',
          timestamp: DateTime.now(),
        ),
        Message(
          sender: 'ai',
          text: 'Here is info.',
          timestamp: DateTime.now(),
          reasoningTrace: const ReasoningTrace(
            matchedTrek: 'everest_base_camp',
            toolsUsed: ['get_trek_details'],
            toolCalls: [],
            toolResults: [],
            sourceFiles: [],
            executionTimeMs: 12,
          ),
        ),
      ];

      final derived = appState.getDerivedContextFromHistory(messages);
      expect(derived['trekId'], 'everest_base_camp');
      expect(derived['tool'], 'get_trek_details');
    });

    test(
      'should filter out sentinel matchedTreks (Sentinel Filtering Check)',
      () {
        final messages = [
          Message(
            sender: 'ai',
            text: 'First details EBC',
            timestamp: DateTime.now(),
            reasoningTrace: const ReasoningTrace(
              matchedTrek: 'everest_base_camp',
              toolsUsed: ['get_trek_details'],
              toolCalls: [],
              toolResults: [],
              sourceFiles: [],
              executionTimeMs: 10,
            ),
          ),
          Message(
            sender: 'user',
            text: 'show all treks',
            timestamp: DateTime.now(),
          ),
          Message(
            sender: 'ai',
            text: 'Here are all treks.',
            timestamp: DateTime.now(),
            reasoningTrace: const ReasoningTrace(
              matchedTrek: 'all', // sentinel!
              toolsUsed: ['list_available_treks'],
              toolCalls: [],
              toolResults: [],
              sourceFiles: [],
              executionTimeMs: 15,
            ),
          ),
        ];

        final derived = appState.getDerivedContextFromHistory(messages);
        expect(derived['trekId'], 'everest_base_camp');
        expect(derived['tool'], 'get_trek_details');
      },
    );
  });

  group('AppState router output parsing and normalization tests', () {
    late AppState appState;

    setUp(() {
      appState = AppState(
        sttService: FakeSttService(),
        ttsService: FakeTtsService(),
      );
    });

    test('valid tool names are left untouched', () {
      final res1 = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: get_trek_details\nCategory: route',
      );
      expect(res1['tool_name'], 'get_trek_details');

      final res2 = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: list_available_treks',
      );
      expect(res2['tool_name'], 'list_available_treks');
    });

    test('invalid tool names containing faq map to get_trek_details', () {
      final res1 = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: get_faq',
      );
      expect(res1['tool_name'], 'get_trek_details');

      final res2 = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: trek_faq',
      );
      expect(res2['tool_name'], 'get_trek_details');
    });

    test(
      'invalid tool names containing list/available map to list_available_treks',
      () {
        final res1 = appState.parseRouterOutputForTesting(
          'Type: tool\nTool: list_treks',
        );
        expect(res1['tool_name'], 'list_available_treks');

        final res2 = appState.parseRouterOutputForTesting(
          'Type: tool\nTool: available_treks',
        );
        expect(res2['tool_name'], 'list_available_treks');
      },
    );

    test(
      'invalid tool names starting with get_trek or containing detail map to get_trek_details',
      () {
        final res1 = appState.parseRouterOutputForTesting(
          'Type: tool\nTool: get_treks\nCategory: villages',
        );
        expect(res1['tool_name'], 'get_trek_details');

        final res2 = appState.parseRouterOutputForTesting(
          'Type: tool\nTool: get_trek\nCategory: route',
        );
        expect(res2['tool_name'], 'get_trek_details');

        final res3 = appState.parseRouterOutputForTesting(
          'Type: tool\nTool: trek_details\nCategory: accommodation',
        );
        expect(res3['tool_name'], 'get_trek_details');
      },
    );

    test('unrecognized tool with active category maps to get_trek_details', () {
      final res = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: query\nCategory: route',
      );
      expect(res['tool_name'], 'get_trek_details');
    });

    test('unrecognized tool with no category defaults to get_trek_details', () {
      final res = appState.parseRouterOutputForTesting(
        'Type: tool\nTool: query\nCategory: none',
      );
      expect(res['tool_name'], 'get_trek_details');
    });

    // Fix 2: bare tool-name recovery (no 'Type:' label emitted by router LLM)
    test('bare "get_trek_details" with no Type label resolves to tool', () {
      final res = appState.parseRouterOutputForTesting('get_trek_details');
      expect(res['type'], 'tool');
      expect(res['tool_name'], 'get_trek_details');
    });

    test('bare "list_available_treks" with no Type label resolves to tool', () {
      final res = appState.parseRouterOutputForTesting('list_available_treks');
      expect(res['type'], 'tool');
      expect(res['tool_name'], 'list_available_treks');
    });

    test('well-formed chat response is unchanged by Fix 2', () {
      final res = appState.parseRouterOutputForTesting(
        'Type: chat\nResponse: Hello!',
      );
      expect(res['type'], 'chat');
      expect(res['chat_response'], 'Hello!');
    });

    test(
      'garbage output falls back to chat (ROUTER PARSE FALLBACK logged)',
      () {
        // We cannot assert on print() output in unit tests, but we can confirm
        // the result is still a safe chat default (not a crash or tool call).
        final res = appState.parseRouterOutputForTesting('garbage output xyz');
        expect(res['type'], 'chat');
      },
    );
  });

  group('_isListingQuery helper tests (via isListingQueryForTesting)', () {
    late AppState appState;

    setUp(() {
      appState = AppState(
        sttService: FakeSttService(),
        ttsService: FakeTtsService(),
      );
    });

    // Positive cases — must return true
    test('"which treks do you have?" -> true', () {
      expect(
        appState.isListingQueryForTesting('which treks do you have?'),
        isTrue,
      );
    });

    test('"what treks do you have" -> true', () {
      expect(
        appState.isListingQueryForTesting('what treks do you have'),
        isTrue,
      );
    });

    test('"what treks are available" -> true', () {
      expect(
        appState.isListingQueryForTesting('what treks are available'),
        isTrue,
      );
    });

    test('"show me other trek options" -> true', () {
      expect(
        appState.isListingQueryForTesting('show me other trek options'),
        isTrue,
      );
    });

    test('"list all treks" -> true', () {
      expect(appState.isListingQueryForTesting('list all treks'), isTrue);
    });

    // Negative cases — must return false
    test('"what is the itinerary for annapurna base camp" -> false', () {
      expect(
        appState.isListingQueryForTesting(
          'what is the itinerary for annapurna base camp',
        ),
        isFalse,
      );
    });

    test('"hello" -> false', () {
      expect(appState.isListingQueryForTesting('hello'), isFalse);
    });

    test('"do I need trekking poles" -> false', () {
      // "trek" appears inside "trekking" — verify the helper does NOT
      // false-positive on substring matches when no listing signal is present.
      expect(
        appState.isListingQueryForTesting('do I need trekking poles'),
        isFalse,
      );
    });
  });
}
