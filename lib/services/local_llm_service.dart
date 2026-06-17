// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:flutter/foundation.dart';

abstract class LlmService {
  Future<void> loadModel(String modelPath, {int contextWindow = 2048});
  Future<void> unloadModel();
  Stream<String> generate(String prompt, {int maxTokens = 512});
  Future<String> generateText(String prompt, {int maxTokens = 512});
  void cancelGeneration();
  bool get isModelLoaded;
}

class LocalLlmService implements LlmService {
  LlamaEngine? _engine;
  EngineSession? _session;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isLoadCancelled = false;
  StreamSubscription<GenerationEvent>? _activeGenSub;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> loadModel(String modelPath, {int contextWindow = 2048}) async {
    if (_isLoading) return;
    _isLoading = true;
    _isLoadCancelled = false;

    // 1. Unload any existing model/engine first to release RAM
    await _cleanUpResources();

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError(
          'Real local inference is only supported on Android, iOS, macOS, Windows, or Linux.',
        );
      }

      final file = File(modelPath);
      if (!await file.exists() || await file.length() == 0) {
        throw FileSystemException(
          'GGUF model file not found or corrupted.',
          modelPath,
        );
      }

      if (_isLoadCancelled) {
        throw Exception('Model loading was cancelled.');
      }

      // 2. Initialize the LlamaEngine worker isolate
      debugPrint(
        'Spawning LlamaEngine with model path: $modelPath (contextWindow: $contextWindow)...',
      );

      final LlamaEngine engine;
      if (Platform.isIOS) {
        engine = await LlamaEngine.spawnFromProcess(
          modelParams: ModelParams(path: modelPath),
          contextParams: ContextParams(nCtx: contextWindow),
        );
      } else {
        final libPath = Platform.isAndroid
            ? 'libllama.so'
            : Platform.isWindows
            ? 'llama.dll'
            : Platform.isMacOS
            ? 'libllama.dylib'
            : Platform.isLinux
            ? 'libllama.so'
            : '';
        engine = await LlamaEngine.spawn(
          libraryPath: libPath,
          modelParams: ModelParams(path: modelPath),
          contextParams: ContextParams(nCtx: contextWindow),
        );
      }

      if (_isLoadCancelled) {
        engine.dispose();
        throw Exception('Model loading was cancelled.');
      }

      _engine = engine;

      // 3. Create the off-thread session
      debugPrint('Creating session for engine...');
      _session = await engine.createSession();

      if (_isLoadCancelled) {
        await unloadModel();
        throw Exception('Model loading was cancelled.');
      }

      _isLoaded = true;
      _isLoading = false;

      // 4. Perform a model warmup to reduce first-response latency
      debugPrint('Performing model warmup prompt...');
      await _warmup();
      debugPrint('Model loaded and warmed up successfully.');
    } catch (e) {
      _isLoaded = false;
      _isLoading = false;
      _session = null;
      _engine?.dispose();
      _engine = null;
      rethrow;
    }
  }

  Future<void> _cleanUpResources() async {
    _activeGenSub?.cancel();
    _activeGenSub = null;

    if (_session != null) {
      try {
        await _session!.dispose();
      } catch (e) {
        debugPrint('Error disposing session: $e');
      }
      _session = null;
    }

    if (_engine != null) {
      debugPrint('Disposing engine...');
      await _engine!.dispose();
      _engine = null;
    }
  }

  @override
  Future<void> unloadModel() async {
    _isLoaded = false;
    _isLoading = false;
    _isLoadCancelled = true;

    await _cleanUpResources();
    // Force garbage collection hint
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  @override
  Stream<String> generate(String prompt, {int maxTokens = 512}) {
    debugPrint('================================');
    debugPrint('GENERATE() CALLED');
    debugPrint('Prompt length: ${prompt.length}');
    debugPrint('PROMPT START');
    debugPrint(prompt);
    debugPrint('PROMPT END');
    debugPrint('================================');

    if (!_isLoaded || _session == null) {
      return Stream.error(
        StateError(
          'No model loaded. You must load a model before generating text.',
        ),
      );
    }

    late final StreamController<String> controller;
    bool isCancelled = false;
    StreamSubscription<GenerationEvent>? localSub;

    controller = StreamController<String>(
      onCancel: () {
        isCancelled = true;
        localSub?.cancel();
      },
    );

    _activeGenSub?.cancel();
    _activeGenSub = null;

    Future.microtask(() async {
      if (isCancelled) return;
      try {
        await _session!.clear();
        if (isCancelled) return;

        debugPrint('Starting llama generation...');

        final eventStream = _session!.generate(
          prompt: prompt,
          maxTokens: maxTokens,
        );

        localSub = eventStream.listen(
          (event) {
            if (event is TokenEvent) {
              controller.add(event.text);
            } else if (event is DoneEvent) {
              if (event.trailingText.isNotEmpty) {
                controller.add(event.trailingText);
              }
              controller.close();
            }
          },
          onError: (err) {
            debugPrint('GENERATION ERROR: $err');
            if (!controller.isClosed) {
              controller.addError(err);
              controller.close();
            }
          },
          onDone: () {
            debugPrint('GENERATION DONE');
            if (!controller.isClosed) {
              controller.close();
            }
          },
          cancelOnError: true,
        );
        _activeGenSub = localSub;
      } catch (e, stackTrace) {
        debugPrint('GENERATION EXCEPTION: $e');
        debugPrint(stackTrace.toString());

        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  @override
  Future<String> generateText(String prompt, {int maxTokens = 512}) async {
    final buffer = StringBuffer();
    await for (final token in generate(prompt, maxTokens: maxTokens)) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  // Prompt builders

  String buildRouterPrompt({
    required List<Map<String, dynamic>> messages,
    required List<String> availableTreks,
  }) {
    final buf = StringBuffer();
    buf.writeln('<|im_start|>system');
    buf.writeln('You are an offline query router for a Nepal trekking app.');
    buf.writeln('Your job is to classify the user\'s last query into one of two Types:');
    buf.writeln('1. "chat": For general greetings, chit-chat, jokes, thanks, or questions unrelated to Nepal treks.');
    buf.writeln('2. "tool": For specific questions about Nepal treks, difficulty, altitude, itinerary, landmarks, villages, accommodations, medical help, safety, transport, packing, or FAQs.');
    buf.writeln('');
    buf.writeln('Available Trek Names:');
    for (final trek in availableTreks) {
      buf.writeln('- "$trek"');
    }
    buf.writeln('');
    buf.writeln('If the Type is "tool", specify the ToolName and Category/Question:');
    buf.writeln('- ToolNames:');
    buf.writeln('  * "list_available_treks": If the user wants a list of available treks or is comparing treks.');
    buf.writeln('  * "get_trek_overview": For general description, difficulty, duration, best season, altitude, or general queries about a specific trek.');
    buf.writeln('  * "get_trek_details": For specific details on a trek. Must specify one of these Categories:');
    buf.writeln('    - "route": itinerary, route, trail, path, map, distance, days');
    buf.writeln('    - "landmarks": sights, peaks, viewpoints, highlights, mountains');
    buf.writeln('    - "villages": tea houses, lodges, accommodation, stays, hotels');
    buf.writeln('    - "hospitals": clinics, medical aid, doctors, health posts');
    buf.writeln('    - "emergency": safety, rescue, contacts, evacuation, dangers');
    buf.writeln('    - "transport": travel, bus, flight, jeep, airport, how to get there');
    buf.writeln('  * "get_trek_faq": For general questions (food, water, Wi-Fi, electricity, gear, SIM card, permits, costs, ATMs). Specify the Question parameter.');
    buf.writeln('');
    buf.writeln('Format your output EXACTLY like one of these two blocks, with no markdown backticks, prose, or introductions:');
    buf.writeln('=== FORMAT FOR CHAT ===');
    buf.writeln('Type: chat');
    buf.writeln('ChatResponse: [Write a friendly direct reply to the user\'s message here]');
    buf.writeln('=======================');
    buf.writeln('');
    buf.writeln('=== FORMAT FOR TOOL ===');
    buf.writeln('Type: tool');
    buf.writeln('TrekName: [Name of the trek, e.g. annapurna_base_camp, everest_base_camp, langtang_valley_base, or "none"]');
    buf.writeln('ToolName: [Name of the tool, e.g. get_trek_details]');
    buf.writeln('Category: [Category string for get_trek_details, or "none"]');
    buf.writeln('Question: [User\'s specific query for get_trek_faq, or "none"]');
    buf.writeln('=======================');
    buf.writeln('<|im_end|>');

    for (final msg in messages) {
      final role = (msg['role'] as String? ?? 'user').trim();
      final content = msg['content']?.toString() ?? '';
      buf.writeln('<|im_start|>$role');
      buf.writeln(content);
      buf.write('<|im_end|>\n');
    }

    buf.writeln('<|im_start|>assistant');
    return buf.toString();
  }

  String buildRephrasePrompt({
    required String context,
    required List<Map<String, dynamic>> messages,
  }) {
    final buf = StringBuffer();
    buf.writeln('<|im_start|>system');
    buf.writeln('You are a helpful Nepal trekking assistant.');
    buf.writeln('Answer the user\'s question ONLY using the verified offline information in the CONTEXT block below.');
    buf.writeln('Be direct, concise, and accurate. Do NOT make up any facts or details not present in the CONTEXT.');
    buf.writeln('If the CONTEXT says no data was found or doesn\'t have the details, politely say: "I don\'t have that information in my offline database."');
    buf.writeln('');
    buf.writeln('=== CONTEXT ===');
    buf.writeln(context);
    buf.writeln('===============');
    buf.writeln('<|im_end|>');

    for (final msg in messages) {
      final role = (msg['role'] as String? ?? 'user').trim();
      final content = msg['content']?.toString() ?? '';
      buf.writeln('<|im_start|>$role');
      buf.writeln(content);
      buf.write('<|im_end|>\n');
    }

    buf.writeln('<|im_start|>assistant');
    return buf.toString();
  }

  @override
  void cancelGeneration() {
    _activeGenSub?.cancel();
    _activeGenSub = null;
  }

  Future<void> _warmup() async {
    if (_session == null) return;
    try {
      final warmupStream = _session!.generate(prompt: '\n', maxTokens: 1);
      await for (final _ in warmupStream) {
        // consume the single token stream to trigger warm up
      }
    } catch (e) {
      debugPrint('Warmup warning: $e');
    }
  }
}
