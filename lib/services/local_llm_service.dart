// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:flutter/foundation.dart';
import '../models/trek_data.dart';

abstract class LlmService {
  Future<void> loadModel(
    String modelPath, {
    int contextWindow = 4096,
    String? modelLabel,
    int? batchSize,
    int? threads,
  });
  Future<void> unloadModel();
  Stream<String> generate(String prompt, {int maxTokens = 1024, String label = 'Generation'});
  Future<String> generateText(String prompt, {int maxTokens = 1024, String label = 'Generation'});
  void cancelGeneration();
  bool get isModelLoaded;
}

class LocalLlmService implements LlmService {
  static int defaultThreads = max(1, Platform.numberOfProcessors - 1);
  static int? defaultBatchSize;
  static int? defaultUbatchSize;

  LlamaEngine? _engine;
  EngineSession? _session;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isLoadCancelled = false;
  StreamSubscription<GenerationEvent>? _activeGenSub;
  String _modelLabel = 'unknown';
  int? _requestedContextWindow;
  int? _requestedBatchSize;
  int? _requestedThreads;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> loadModel(
    String modelPath, {
    int contextWindow = 4096,
    String? modelLabel,
    int? batchSize,
    int? threads,
  }) async {
    if (_isLoading) return;
    _isLoading = true;
    _isLoadCancelled = false;

    final loadStopwatch = Stopwatch()..start();

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

      final resolvedThreads = threads ?? defaultThreads;
      final contextParams = ContextParams(
        nCtx: contextWindow,
        nBatch: batchSize ?? defaultBatchSize ?? const ContextParams().nBatch,
        nUbatch: defaultUbatchSize ?? const ContextParams().nUbatch,
        nThreads: resolvedThreads,
        nThreadsBatch: resolvedThreads,
      );
      _modelLabel = modelLabel ?? file.uri.pathSegments.last;
      _requestedContextWindow = contextParams.nCtx;
      _requestedBatchSize = contextParams.nBatch;
      _requestedThreads = contextParams.nThreads;

      debugPrint(
        '===== MODEL LOAD =====\n'
        'Model: $_modelLabel\n'
        'Model Path: $modelPath\n'
        'Platform Processors: ${Platform.numberOfProcessors}\n'
        'Requested Context: ${contextParams.nCtx}\n'
        'Requested Batch Size: ${contextParams.nBatch}\n'
        'Requested UBatch Size: ${contextParams.nUbatch}\n'
        'Requested Threads: ${_formatThreads(contextParams.nThreads)}\n'
        'Requested Batch Threads: ${_formatThreads(contextParams.nThreadsBatch)}',
      );

      // 2. Initialize the LlamaEngine worker isolate
      debugPrint(
        'Spawning LlamaEngine with model path: $modelPath (contextWindow: $contextWindow)...',
      );

      final LlamaEngine engine;
      if (Platform.isIOS) {
        engine = await LlamaEngine.spawnFromProcess(
          modelParams: ModelParams(path: modelPath),
          contextParams: contextParams,
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
          contextParams: contextParams,
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
      _logSessionCreated(engine);

      if (_isLoadCancelled) {
        await unloadModel();
        throw Exception('Model loading was cancelled.');
      }

      _isLoaded = true;
      _isLoading = false;

      // 4. Perform a model warmup to reduce first-response latency
      debugPrint('Performing model warmup prompt...');
      await _warmup();
      
      loadStopwatch.stop();
      debugPrint('Model loaded and warmed up successfully in ${loadStopwatch.elapsedMilliseconds}ms.');
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
  Stream<String> generate(String prompt, {int maxTokens = 1024, String label = 'Generation'}) {
    final estimatedPromptTokens = _estimateTokenCount(prompt);
    final estimatedRemaining = _remainingContextAfterPrompt(
      estimatedPromptTokens,
    );
    debugPrint(
      '===== GENERATION REQUEST ($label) =====\n'
      'Model: $_modelLabel\n'
      'Prompt Length: ${prompt.length}\n'
      'Estimated Tokens: $estimatedPromptTokens\n'
      'Max Tokens: $maxTokens\n'
      'Configured Context: ${_requestedContextWindow ?? 'unknown'}\n'
      'Estimated Remaining Context: ${estimatedRemaining ?? 'unknown'}\n'
      'Estimated Prompt Can Exceed Context: ${_canExceedContext(estimatedPromptTokens, maxTokens)}',
    );

    if (!_isLoaded || _session == null) {
      return Stream.error(
        StateError(
          'No model loaded. You must load a model before generating text.',
        ),
      );
    }

    final totalStopwatch = Stopwatch()..start();
    final prefillStopwatch = Stopwatch()..start();
    final decodeStopwatch = Stopwatch();
    var prefillLogged = false;
    var generatedTokens = 0;
    var timingLogged = false;

    void logTiming(String status, {int? forcedTokenCount}) {
      if (timingLogged) return;
      timingLogged = true;
      totalStopwatch.stop();
      if (prefillLogged) {
        decodeStopwatch.stop();
      } else {
        prefillStopwatch.stop();
      }
      _logGenerationTiming(
        label: label,
        prefillMs: prefillStopwatch.elapsedMilliseconds,
        decodeMs: decodeStopwatch.elapsedMilliseconds,
        totalMs: totalStopwatch.elapsedMilliseconds,
        tokenCount: forcedTokenCount ?? generatedTokens,
        status: status,
      );
    }

    late final StreamController<String> controller;
    bool isCancelled = false;
    StreamSubscription<GenerationEvent>? localSub;

    controller = StreamController<String>(
      onCancel: () {
        isCancelled = true;
        localSub?.cancel();
        logTiming('CANCELLED');
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
              if (!prefillLogged) {
                prefillLogged = true;
                prefillStopwatch.stop();
                decodeStopwatch.start();
                _logActualGenerationWindow(
                  promptTokens: event.position,
                  maxTokens: maxTokens,
                );
              }
              generatedTokens++;
              controller.add(event.text);
            } else if (event is DoneEvent) {
              debugPrint(
                '[LLM] Generation done: reason=${event.reason}, '
                'generatedTokens=${event.generatedCount}, '
                'committedPosition=${event.committedPosition}',
              );
              if (event.trailingText.isNotEmpty) {
                controller.add(event.trailingText);
              }
              logTiming('SUCCESS', forcedTokenCount: event.generatedCount > 0 ? event.generatedCount : null);
              controller.close();
            }
          },
          onError: (err) {
            _logGenerationFailure(
              error: err,
              prompt: prompt,
              maxTokens: maxTokens,
            );
            logTiming('FAILED');
            if (!controller.isClosed) {
              controller.addError(err);
              controller.close();
            }
          },
          onDone: () {
            debugPrint('GENERATION DONE');
            logTiming('SUCCESS');
            if (!controller.isClosed) {
              controller.close();
            }
          },
          cancelOnError: true,
        );
        _activeGenSub = localSub;
      } catch (e, stackTrace) {
        _logGenerationFailure(
          error: e,
          prompt: prompt,
          maxTokens: maxTokens,
          stackTrace: stackTrace,
        );
        logTiming('FAILED');

        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  @override
  Future<String> generateText(String prompt, {int maxTokens = 1024, String label = 'Generation'}) async {
    final buffer = StringBuffer();
    await for (final token in generate(prompt, maxTokens: maxTokens, label: label)) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  void _logGenerationTiming({
    required String label,
    required int prefillMs,
    required int decodeMs,
    required int totalMs,
    required int tokenCount,
    String status = 'SUCCESS',
  }) {
    final decodeSec = decodeMs / 1000.0;
    final tokensPerSec = decodeSec > 0 ? tokenCount / decodeSec : 0.0;
    debugPrint(
      '===== GENERATION TIMING ($label) =====\n'
      'Status: $status\n'
      'Prefill Latency: ${prefillMs}ms\n'
      'Decode Latency: ${decodeMs}ms\n'
      'Total Generation Time: ${totalMs}ms\n'
      'Generated Tokens: $tokenCount\n'
      'Throughput: ${tokensPerSec.toStringAsFixed(2)} tokens/sec\n'
      '======================================',
    );
  }

  // Prompt builders

  String buildRouterPrompt({
    required List<Map<String, dynamic>> messages,
    bool hasSelectedTrek = false,
    String? lastResolvedTrek,
    String? lastResolvedTool,
    List<String> availableTreks = const [],
  }) {
    final buf = StringBuffer();
    buf.writeln('<|im_start|>system');
    buf.writeln('You are a router only.');
    buf.writeln('You are NOT an assistant.');
    buf.writeln('Your only job is to classify the user query.');
    buf.writeln('');
    buf.writeln(hasSelectedTrek
        ? 'Context: A trek IS currently selected.'
        : 'Context: No trek is currently selected.');

    if (lastResolvedTrek != null && lastResolvedTrek.isNotEmpty &&
        lastResolvedTool != null && lastResolvedTool.isNotEmpty) {
      buf.writeln('Context: Last topic was $lastResolvedTrek ($lastResolvedTool).');
    } else {
      if (lastResolvedTrek != null && lastResolvedTrek.isNotEmpty) {
        buf.writeln('Context: Last topic was $lastResolvedTrek.');
      }
      if (lastResolvedTool != null && lastResolvedTool.isNotEmpty) {
        buf.writeln('Context: Last resolved tool was $lastResolvedTool.');
      }
    }
    buf.writeln('');

    buf.writeln('Possible outputs:');
    buf.writeln('');

    buf.writeln('For normal chat:');
    buf.writeln('Type: chat');
    buf.writeln('Response: <short response>');
    buf.writeln('');

    buf.writeln('For trekking information:');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_details | get_trek_faq | list_available_treks');
    buf.writeln('- Category is required only for get_trek_details.');
    buf.writeln(
      'The categories are: ${TrekCategory.values.map((c) => c.name).join(' | ')}',
    );
    buf.writeln('');

    buf.writeln('Rules:');
    buf.writeln('- Never answer trekking questions.');
    buf.writeln('- Never provide trekking facts.');
    buf.writeln('- Never explain your reasoning.');
    buf.writeln('- Never output JSON.');
    buf.writeln('- Output ONLY one of the supported formats.');
    buf.writeln('- Greetings, thanks, jokes, casual conversation -> chat.');
    buf.writeln('- Trek information requests -> tool.');
    buf.writeln(
      '- If a trek is selected and the user asks about that trek specifically (details, itinerary, info, "tell me about it"), use get_trek_details, NOT list_available_treks.',
    );
    buf.writeln(
      '- Use list_available_treks ONLY when the user asks to see multiple treks, browse options, or compare treks — not when asking about the one already selected.',
    );
    buf.writeln(
      '- Use get_trek_faq for gear, packing, costs, guides, porters, maps, SIM, ATM, charging, permits, food, water, and other common trek questions.',
    );
    buf.writeln(
      '- Use get_trek_details for route, itinerary, villages, accommodation, landmarks, hospitals, emergency, transport, weather, connectivity and other trek facts.',
    );

    buf.writeln('');
    buf.writeln('Examples:');
    buf.writeln('');
    buf.writeln('User: Hello');
    buf.writeln('Type: chat');
    buf.writeln('Response: Hello! How can I help you?');
    buf.writeln('');

    buf.writeln('User: What is the itinerary?');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_details');
    buf.writeln('Category: route');
    buf.writeln('');

    buf.writeln('User: Where are the hospitals?');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_details');
    buf.writeln('Category: hospitals');
    buf.writeln('');

    buf.writeln('User: What permits are required?');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_details');
    buf.writeln('Category: permits');
    buf.writeln('');

    buf.writeln('User: Do I need trekking poles?');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_faq');
    buf.writeln('');

    buf.writeln('User: tell me about everest base camp');
    buf.writeln('Type: tool');
    buf.writeln('Tool: get_trek_details');
    buf.writeln('Category: info');
    buf.writeln('');

    buf.writeln('User: what treks do you have');
    buf.writeln('Type: tool');
    buf.writeln('Tool: list_available_treks');
    buf.writeln('');

    buf.writeln('<|im_end|>');

    for (final msg in messages) {
      final role = (msg['role'] as String? ?? 'user').trim();
      final content = msg['content']?.toString() ?? '';
      buf.writeln('<|im_start|>$role');
      buf.writeln(
        content,
      ); // LLM is unable to return the details in proper format. The selected catgegory or tool should be called by dart and information should be normalized and given to the LLM2
      buf.write('<|im_end|>\n');
    }

    buf.writeln('<|im_start|>assistant');
    return buf.toString();
    // After first LLM finishes its job, and dart calls and executes the tool, the response is only sent to the LLM 2.
  }

  String buildRephrasePrompt({
    required String context,
    required List<Map<String, dynamic>> messages,
  }) {
    final buf = StringBuffer();
    buf.writeln('<|im_start|>system');
    buf.writeln('You are a helpful offline Nepal trekking assistant.');
    buf.writeln(
      'Answer the user\'s question using ONLY the facts listed below.',
    );
    buf.writeln('');
    buf.writeln('Rules:');
    buf.writeln(
      '1. Do not assume, extrapolate, or mention external knowledge.',
    );
    buf.writeln(
      '2. If the provided facts do not contain the answer, reply: "I do not have that information in my offline database."',
    );
    buf.writeln(
      '3. Be thorough and complete. For itinerary or route questions, list all days. Do not mention "facts", "JSON", or "database".',
    );
    buf.writeln('');
    buf.writeln('=== FACTS ===');
    buf.writeln(
      context,
    ); // Here the response from the tool should be received with proper format
    buf.writeln('=============');
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

  void _logSessionCreated(LlamaEngine engine) {
    final accelerator = engine.primaryAcceleratorName ?? 'CPU/default backend';
    final devices = engine.devices.isEmpty
        ? 'not reported'
        : engine.devices
              .map((device) => '${device.registryName}:${device.name}')
              .join(', ');
    debugPrint(
      '===== SESSION CREATED =====\n'
      'Actual Context: unavailable via LlamaEngine API '
      '(requested ${_requestedContextWindow ?? 'unknown'})\n'
      'Actual Batch Size: unavailable via LlamaEngine API '
      '(requested ${_requestedBatchSize ?? 'unknown'})\n'
      'Actual Threads: unavailable via LlamaEngine API '
      '(requested ${_requestedThreads == null ? 'unknown' : _formatThreads(_requestedThreads!)})\n'
      'Context Shift Supported: ${engine.canShift}\n'
      'Primary Accelerator: $accelerator\n'
      'Backend Devices: $devices\n'
      'Actual values are available inside llama_cpp_dart as '
      'LlamaContext.nCtx/nBatch/nThreads, but they are not forwarded by '
      'LlamaEngine/EngineSession.',
    );
  }

  void _logActualGenerationWindow({
    required int promptTokens,
    required int maxTokens,
  }) {
    final remaining = _remainingContextAfterPrompt(promptTokens);
    debugPrint(
      '===== GENERATION =====\n'
      'Prompt Tokens: $promptTokens\n'
      'Max Tokens: $maxTokens\n' // what is the use of maxTokens? why is it not included in the request and returned in the response? what if the user asks for a long response?
      'Remaining Context: ${remaining ?? 'unknown'}\n'
      'Configured Context: ${_requestedContextWindow ?? 'unknown'}\n'
      'Prompt Can Exceed Context: ${_canExceedContext(promptTokens, maxTokens)}\n'
      'Prompt Token Source: first TokenEvent.position after prefill',
    );
  }

  void _logGenerationFailure({
    required Object error,
    required String prompt,
    required int maxTokens,
    StackTrace? stackTrace,
  }) {
    final estimatedPromptTokens = _estimateTokenCount(prompt);
    final estimatedRemaining = _remainingContextAfterPrompt(
      estimatedPromptTokens,
    );
    debugPrint(
      '===== GENERATION FAILED =====\n'
      'Model: $_modelLabel\n'
      'Configured Context: ${_requestedContextWindow ?? 'unknown'}\n'
      'Prompt Length: ${prompt.length}\n'
      'Estimated Tokens: $estimatedPromptTokens\n'
      'Max Tokens: $maxTokens\n'
      'Estimated Remaining Context: ${estimatedRemaining ?? 'unknown'}\n'
      'Estimated Prompt Can Exceed Context: ${_canExceedContext(estimatedPromptTokens, maxTokens)}\n'
      'Error: $error',
    );
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  int _estimateTokenCount(String text) => (text.length / 4.0).ceil();

  int? _remainingContextAfterPrompt(int promptTokens) {
    final contextWindow = _requestedContextWindow;
    if (contextWindow == null) return null;
    return contextWindow - promptTokens;
  }

  String _canExceedContext(int promptTokens, int maxTokens) {
    final contextWindow = _requestedContextWindow;
    if (contextWindow == null) return 'unknown';
    return (promptTokens + maxTokens > contextWindow).toString();
  }

  String _formatThreads(int threads) {
    if (threads == 0) return '0 (llama.cpp auto)';
    return threads.toString();
  }
}
