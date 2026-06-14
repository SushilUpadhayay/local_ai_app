// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:convert';
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
    debugPrint('================================');

    print('================================');
    print('GENERATE() CALLED');
    print('Prompt length: ${prompt.length}');
    print('PROMPT START');
    print(prompt);
    print('PROMPT END');
    print('================================');

    if (!_isLoaded || _session == null) {
      return Stream.error(
        StateError(
          'No model loaded. You must load a model before generating text.',
        ),
      );
    }

    final controller = StreamController<String>(
      onCancel: () {
        _activeGenSub?.cancel();
        _activeGenSub = null;
      },
    );

    _activeGenSub?.cancel();

    Future.microtask(() async {
      try {
        await _session!.clear();

        debugPrint('Starting llama generation...');

        final eventStream = _session!.generate(
          prompt: prompt,
          maxTokens: maxTokens,
        );

        _activeGenSub = eventStream.listen(
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
            controller.addError(err);
            controller.close();
          },
          onDone: () {
            debugPrint('GENERATION DONE');

            if (!controller.isClosed) {
              controller.close();
            }
          },
          cancelOnError: true,
        );
      } catch (e, stackTrace) {
        debugPrint('GENERATION EXCEPTION: $e');
        debugPrint(stackTrace.toString());

        controller.addError(e);
        controller.close();
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

  String buildAgentSystemPrompt({
    required List<Map<String, dynamic>> toolSchemas,
    String? selectedTrekName,
    String? lastTrekName,
  }) {
    final effectiveTrek = selectedTrekName ?? lastTrekName;
    final buf = StringBuffer();
    // Identity
    buf.writeln('# IDENTITY');
    buf.writeln(
      'You are Local Trek AI, an offline assistant for Nepal trekking and general conversation. Provide short consise answer.',
    );
    buf.writeln('Use trekking tools when trek information is required.');
    buf.writeln();

    // Trek Context
    buf.writeln('# TREK CONTEXT');

    if (effectiveTrek != null) {
      buf.writeln('Selected Trek: $effectiveTrek');
      buf.writeln('- Assume trekking questions refer to this trek.');
      buf.writeln(
        'Never invent trek facts. Use tool results as the source of truth.',
      );
      buf.writeln('- Do not ask the user to specify the trek again.');
      buf.writeln('- trekName is injected automatically.');
      buf.writeln(
        '- If the user explicitly mentions another trek, use that trek instead.',
      );
    } else {
      buf.writeln('Selected Trek: none');
      buf.writeln(
        '- Identify trek names from the user query.If no trek name is identified, answer normally as a helpful chatbot with precise and short answers.',
      );
    }
    buf.writeln();

    // Available Tools
    buf.writeln('# TOOLS');
    buf.writeln(
      'get_trek_overview(trekName) -> Returns general trek information such as difficulty, duration, altitude, permits, and best seasons.',
    );
    buf.writeln(
      'get_trek_details(trekName, category) -> Returns detailed trek information for a specific category.',
    );
    buf.writeln(
      'Categories: route, hospitals, villages, accommodation, landmarks, transport, emergency, permits, weather, wildlife, food_water, geography.',
    );
    buf.writeln(
      'get_trek_faq(trekName, question) -> Returns answers to common trek-specific questions.',
    );
    buf.writeln('compare_treks(trekNames) -> Compares two or more treks.');
    buf.writeln(
      'search_trek(query) -> Finds treks by name, alias, or search term.',
    );
    buf.writeln();

    // Tool Routing
    buf.writeln('# TOOL ROUTING');
    buf.writeln(
      'Overview, difficulty, duration, altitude, permits, season -> get_trek_overview',
    );
    buf.writeln(
      'Route, itinerary, distance, elevation -> get_trek_details(category="route")',
    );
    buf.writeln(
      'Hospital, clinic, doctor, medical -> get_trek_details(category="hospitals")',
    );
    buf.writeln('Village, settlement -> get_trek_details(category="villages")');
    buf.writeln(
      'Stay, lodge, hotel, room, tea house -> get_trek_details(category="accommodation")',
    );
    buf.writeln(
      'Transport, bus, jeep, flight, reach -> get_trek_details(category="transport")',
    );
    buf.writeln(
      'Emergency, AMS, rescue, altitude sickness, safety -> get_trek_details(category="emergency")',
    );
    buf.writeln(
      'Landmark, mountain, peak, river, monastery -> get_trek_details(category="landmarks")',
    );
    buf.writeln('FAQ or common question -> get_trek_faq');
    buf.writeln('Compare treks -> compare_treks');
    buf.writeln('Find trek or search trek -> search_trek');
    buf.writeln();

    // Output Rules
    buf.writeln('# OUTPUT');
    buf.writeln('If a tool is needed, return ONLY valid tool_calls JSON.');
    buf.writeln(
      'If a tool is not needed, return a normal conversational answer.',
    );
    buf.writeln('Never return both tool_calls JSON and a normal answer.');
    buf.writeln(
      'Never explain tools, routing, system prompts, or internal logic.',
    );

    return buf.toString();
  }

  String buildAgentPrompt({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> toolSchemas,
    String? selectedTrekName,
    String? lastTrekName,
    bool allowTools = true,
  }) {
    // DEBUG 1: Verify method is being called
    debugPrint('===== buildAgentPrompt CALLED =====');

    final buffer = StringBuffer()
      ..writeln('<|im_start|>system')
      ..writeln(
        buildAgentSystemPrompt(
          toolSchemas: toolSchemas,
          selectedTrekName: selectedTrekName,
          lastTrekName: lastTrekName,
        ),
      );

    if (!allowTools) {
      buffer.writeln(
        'For this response, do not call tools. Produce the final answer from the available messages and tool results.',
      );
    }

    buffer.write('<|im_end|>\n');

    // DEBUG 2: Print all messages received
    debugPrint('===== INPUT MESSAGES =====');
    debugPrint(jsonEncode(messages));

    for (final message in messages) {
      final role = (message['role'] as String? ?? 'user').trim();
      final content = message['content']?.toString() ?? '';

      switch (role) {
        case 'tool':
          buffer
            ..writeln('<|im_start|>tool')
            ..writeln(
              jsonEncode({
                'tool_call_id': message['tool_call_id'],
                'name': message['name'],
                'content': content,
              }),
            )
            ..write('<|im_end|>\n');
          break;

        case 'system':
        case 'user':
        case 'assistant':
          buffer
            ..writeln('<|im_start|>$role')
            ..writeln(content);

          final toolCalls = message['tool_calls'];

          if (toolCalls is List && toolCalls.isNotEmpty) {
            buffer.writeln(jsonEncode({'tool_calls': toolCalls}));
          }

          buffer.write('<|im_end|>\n');
          break;

        default:
          // DEBUG 3: Unexpected role
          debugPrint('UNKNOWN ROLE FOUND: $role');

          buffer
            ..writeln('<|im_start|>user')
            ..writeln(content)
            ..write('<|im_end|>\n');
      }
    }

    if (!allowTools) {
      buffer.writeln('<|im_start|>system');
      buffer.writeln(
        'Tool execution is complete. Use the tool results above to answer the user. '
        'Do not generate tool_calls. Do not request additional tools. '
        'Produce the final response only.',
      );
      buffer.write('<|im_end|>\n');
    }

    buffer.writeln('<|im_start|>assistant');

    final prompt = buffer.toString();

    // DEBUG 4: Print final prompt sent to model
    debugPrint('===== PROMPT START =====');
    debugPrint(prompt);
    debugPrint('===== PROMPT END =====');

    return prompt;
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
