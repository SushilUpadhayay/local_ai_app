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

  String buildAgentSystemPrompt({
    required List<Map<String, dynamic>> toolSchemas,
    String? selectedTrekName,
    String? lastTrekName,
  }) {
    final effectiveTrek = selectedTrekName ?? lastTrekName;
    final buf = StringBuffer();

    buf.writeln('# IDENTITY');
    buf.writeln(
      'You are a dual-mode assistant for a Nepal Trekking App. Depending on the CONTEXT block below, you will operate as either a friendly conversational chatbot OR a strict, headless JSON API router.',
    );
    buf.writeln();

    buf.writeln('# CONTEXT');
    if (effectiveTrek != null) {
      buf.writeln('Selected Trek: $effectiveTrek');
      buf.writeln(
        '- Use this trek for implicit questions. If a different trek is named, use that instead.',
      );
      buf.writeln(
        '- You have NO native knowledge. Rely ONLY on provided tool results for facts.',
      );
    } else {
      buf.writeln('Selected Trek: none');
      buf.writeln(
        '- Identify trek names from the user query. If no trek name is identified, answer normally as a helpful chatbot.',
      );
      buf.writeln(
        '- You have NO native knowledge. Rely ONLY on provided tool results for facts.',
      );
    }
    buf.writeln();

    buf.writeln('# TOOLS');
    buf.writeln(
      'get_trek_overview(trekName): difficulty, duration, altitude, permits, season',
    );
    buf.writeln(
      'get_trek_details(trekName, category): category in [route, hospitals, villages, accommodation, landmarks, transport, emergency, permits, weather, wildlife, food_water, geography]',
    );
    buf.writeln('get_trek_faq(trekName, question): FAQ answers');
    buf.writeln('compare_treks(trekNames): compare treks');
    buf.writeln('search_trek(query): find treks');
    buf.writeln();

    buf.writeln('# RULES');

    buf.writeln(
      '1. **TREK IDENTIFIED BUT NO DATA:**If a trek is identified but no tool data is present in history, you MUST execute a tool. Output ONLY the JSON block. Do not write prose or explain your logic.',
    );
    buf.writeln(
      '2. **DATA IS PRESENT:** If a `<|im_start|>tool` message or tool result is present in the history, use that data to answer the user directly in 1-2 concise sentences. Do not generate a tool call.',
    );
    buf.writeln();

    buf.writeln('# OUTPUT FORMAT FOR TOOLS');
    buf.writeln(
      'To call a tool, return ONLY valid JSON matching this schema. Replace ID_STRING with a unique identifier:',
    );
    buf.writeln('```json');
    buf.writeln('{');
    buf.writeln('  "tool_calls": [');
    buf.writeln('    {');
    buf.writeln('      "id": "ID_STRING",');
    buf.writeln('      "type": "function",');
    buf.writeln('      "function": {');
    buf.writeln('        "name": "TOOL_NAME",');
    buf.writeln('        "arguments": {"PARAM_NAME": "VALUE"}');
    buf.writeln('      }');
    buf.writeln('    }');
    buf.writeln('  ]');
    buf.writeln('}');
    buf.writeln('```');

    return buf.toString();
  }

  String buildAgentPrompt({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> toolSchemas,
    String? selectedTrekName,
    String? lastTrekName,
    bool allowTools = true,
  }) {
    debugPrint('\n==============================');
    debugPrint('BUILD AGENT PROMPT');
    debugPrint('allowTools: $allowTools');
    debugPrint('selectedTrekName: $selectedTrekName');
    debugPrint('lastTrekName: $lastTrekName');
    debugPrint('messageCount: ${messages.length}');
    debugPrint('==============================\n');

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
      debugPrint('TOOLS DISABLED FOR THIS GENERATION');

      buffer.writeln(
        'For this response, do not call tools. Produce the final answer from the available messages and tool results.',
      );
    }

    buffer.write('<|im_end|>\n');

    debugPrint('\n===== RAW INPUT MESSAGES =====');
    debugPrint(const JsonEncoder.withIndent('  ').convert(messages));
    debugPrint('==============================\n');

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];

      final role = (message['role'] as String? ?? 'user').trim();
      final content = message['content']?.toString() ?? '';

      debugPrint('\n----- MESSAGE $i -----');
      debugPrint('ROLE: $role');
      debugPrint('CONTENT: $content');

      switch (role) {
        case 'tool':
          debugPrint('TOOL MESSAGE FOUND');
          debugPrint('tool_call_id: ${message['tool_call_id']}');
          debugPrint('tool_name: ${message['name']}');
          debugPrint('tool_content: $content');

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
          final toolCalls = message['tool_calls'];

          if (toolCalls != null) {
            debugPrint('TOOL CALLS PRESENT');
            debugPrint(jsonEncode(toolCalls));
          }

          // Detect suspicious assistant messages
          if (role == 'assistant' &&
              content.contains('Tool execution is complete')) {
            debugPrint(
              'WARNING: INTERNAL TOOL INSTRUCTION FOUND IN CHAT HISTORY',
            );
          }

          buffer
            ..writeln('<|im_start|>$role')
            ..writeln(content);

          if (toolCalls is List && toolCalls.isNotEmpty) {
            buffer.writeln(jsonEncode({'tool_calls': toolCalls}));
          }

          buffer.write('<|im_end|>\n');
          break;

        default:
          debugPrint('UNKNOWN ROLE: $role');

          buffer
            ..writeln('<|im_start|>user')
            ..writeln(content)
            ..write('<|im_end|>\n');
      }
    }

    if (!allowTools) {
      debugPrint('ADDING FINAL NO-TOOLS SYSTEM MESSAGE');

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

    debugPrint('\n===== PROMPT STATS =====');
    debugPrint('Prompt length: ${prompt.length}');
    debugPrint('Tool schemas count: ${toolSchemas.length}');
    debugPrint('========================\n');

    debugPrint('\n===== FINAL PROMPT =====');
    debugPrint(prompt);
    debugPrint('===== END PROMPT =====\n');

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
